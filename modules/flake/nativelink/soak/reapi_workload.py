#!/usr/bin/env python3
# Vendored 2026-10-13 from ~/src/b7r6/rechaos-nativelink-raft (no remote; rev
# 1b9c1606b43c8a65d9163e27d8c9f52900740eec) for the Azure soak rig. Byte-identical
# to the harness copy; keep it that way and upstream fixes there.
"""Scheduler-focused REAPI workload + invariant checker for the rechaos harness.

Speaks REAPI directly (rechaos's generated protos, from $RECHAOS_DIR/.build/python)
to an endpoint, normally the rechaos gateway. Two subcommands:

  build   A deterministic three-layer "build" (16 generators -> 4 combiners ->
          1 linker; inputs flow through CAS). Downloads every output into --out
          so `rechaos oracle` can compare a clean tree with a chaos tree.
  stress  A seeded mix of Execute traffic for --seconds: cacheable actions from
          a small pool (cache hits), do_not_cache actions, bursts of concurrent
          IDENTICAL requests (dedup), sleeping actions that are cancelled by the
          client mid-flight (killable), and sleeping actions whose Action.timeout
          is shorter than the sleep (the worker must kill them).

Every logical request runs through `Executor.run`, which survives a scheduler
restart: on a transport error it resumes with WaitExecution(op name); if the
scheduler no longer knows the operation that is recorded as `state-lost` and the
request is re-submitted with Execute.

Invariants checked at the end (see README.md for the mapping to rechaos
docs/invariants.md); each violation is a finding in --report:

  S1 terminal          every request ends in a completed operation with a
                       well-formed ExecuteResponse, or a well-formed gRPC error,
                       before its deadline.
  S2 single-result     one operation name is never reported done with two
                       different results.
  S3 deterministic     every OK completion of the same action digest has the
                       same exit code and output digests (dedup / cache /
                       re-execution must agree).
  S4 expected-outcome  a timed-out action reports DEADLINE_EXCEEDED, a normal
                       action exits 0 with status OK.
  S5 state-retained    an operation the scheduler acknowledged is still known
                       after a scheduler restart (WaitExecution does not fail
                       with NOT_FOUND). With --expect-state-loss (memory
                       backend) violations are counted as baseline, not
                       findings.
"""
import argparse
import collections
import concurrent.futures as cf
import hashlib
import json
import os
import pathlib
import random
import shutil
import sys
import threading
import time
import uuid

import grpc
from build.bazel.remote.execution.v2 import remote_execution_pb2 as re
from google.bytestream import bytestream_pb2 as bs
from google.longrunning import operations_pb2 as lro
from google.protobuf import duration_pb2

INSTANCE = "main"
EXECUTE = "/build.bazel.remote.execution.v2.Execution/Execute"
WAIT = "/build.bazel.remote.execution.v2.Execution/WaitExecution"
BATCH_UPDATE = "/build.bazel.remote.execution.v2.ContentAddressableStorage/BatchUpdateBlobs"
FIND_MISSING = "/build.bazel.remote.execution.v2.ContentAddressableStorage/FindMissingBlobs"
BS_READ = "/google.bytestream.ByteStream/Read"
RETRYABLE = {grpc.StatusCode.UNAVAILABLE, grpc.StatusCode.UNKNOWN, grpc.StatusCode.INTERNAL,
             grpc.StatusCode.CANCELLED, grpc.StatusCode.ABORTED, grpc.StatusCode.RESOURCE_EXHAUSTED}
# Codes a scheduler may legitimately end a request with (a well-formed failure).
TERMINAL_ERRORS = {grpc.StatusCode.FAILED_PRECONDITION, grpc.StatusCode.INVALID_ARGUMENT,
                   grpc.StatusCode.DEADLINE_EXCEEDED, grpc.StatusCode.NOT_FOUND,
                   grpc.StatusCode.PERMISSION_DENIED, grpc.StatusCode.OUT_OF_RANGE,
                   grpc.StatusCode.UNIMPLEMENTED, grpc.StatusCode.DATA_LOSS}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def digest_of(data):
    return re.Digest(hash=sha(data), size_bytes=len(data))


class Client:
    def __init__(self, target):
        self.ch = grpc.insecure_channel(target, options=[
            ("grpc.max_receive_message_length", 64 << 20),
            ("grpc.enable_retries", 0)])
        self.execute = self.ch.unary_stream(EXECUTE, request_serializer=re.ExecuteRequest.SerializeToString,
                                            response_deserializer=lro.Operation.FromString)
        self.wait = self.ch.unary_stream(WAIT, request_serializer=re.WaitExecutionRequest.SerializeToString,
                                         response_deserializer=lro.Operation.FromString)
        self.batch_update = self.ch.unary_unary(
            BATCH_UPDATE, request_serializer=re.BatchUpdateBlobsRequest.SerializeToString,
            response_deserializer=re.BatchUpdateBlobsResponse.FromString)
        self.find_missing = self.ch.unary_unary(
            FIND_MISSING, request_serializer=re.FindMissingBlobsRequest.SerializeToString,
            response_deserializer=re.FindMissingBlobsResponse.FromString)
        self.read = self.ch.unary_stream(BS_READ, request_serializer=bs.ReadRequest.SerializeToString,
                                         response_deserializer=bs.ReadResponse.FromString)
        self.uploaded = set()
        self.lock = threading.Lock()

    def _retry(self, fn, what, deadline_s=90):
        end = time.monotonic() + deadline_s
        delay = 0.2
        while True:
            try:
                return fn()
            except grpc.RpcError as e:
                if e.code() not in RETRYABLE or time.monotonic() > end:
                    raise
                time.sleep(delay)
                delay = min(delay * 2, 3.0)

    def upload(self, blobs):
        """Upload {digest_hash: bytes} that the server reports missing."""
        with self.lock:
            todo = {h: b for h, b in blobs.items() if h not in self.uploaded}
        if not todo:
            return
        digests = [re.Digest(hash=h, size_bytes=len(b)) for h, b in todo.items()]

        def go():
            missing = self.find_missing(re.FindMissingBlobsRequest(
                instance_name=INSTANCE, blob_digests=digests,
                digest_function=re.DigestFunction.SHA256), timeout=20).missing_blob_digests
            if missing:
                resp = self.batch_update(re.BatchUpdateBlobsRequest(
                    instance_name=INSTANCE, digest_function=re.DigestFunction.SHA256,
                    requests=[re.BatchUpdateBlobsRequest.Request(digest=d, data=todo[d.hash])
                              for d in missing]), timeout=30)
                bad = [r for r in resp.responses if r.status.code != 0]
                if bad:
                    raise RuntimeError(f"BatchUpdateBlobs per-blob failure: {bad[0].status}")
        self._retry(go, "upload")
        with self.lock:
            self.uploaded.update(todo)

    def fetch(self, d):
        def go():
            name = f"{INSTANCE}/blobs/{d.hash}/{d.size_bytes}"
            data = b"".join(r.data for r in self.read(bs.ReadRequest(resource_name=name), timeout=30))
            if sha(data) != d.hash:
                raise RuntimeError(f"read of {d.hash} returned wrong bytes")
            return data
        if d.size_bytes == 0:
            return b""
        return self._retry(go, "read")


# --------------------------------------------------------------------------- #
# Actions
# --------------------------------------------------------------------------- #
class ActionSpec:
    """A Command + input root + Action, fully materialised as blobs."""

    def __init__(self, kind, script, inputs=None, do_not_cache=False, timeout_s=0, salt=b"",
                 outputs=(), expect="ok", path_env=""):
        self.kind, self.expect = kind, expect
        plat = re.Platform(properties=[re.Platform.Property(name="OSFamily", value="linux")])
        cmd = re.Command(
            arguments=["/bin/sh", "-c", script],
            environment_variables=[re.Command.EnvironmentVariable(name="PATH", value=path_env)],
            output_paths=sorted(outputs), platform=plat)
        self.blobs = {}
        cmd_b = cmd.SerializeToString()
        self.blobs[sha(cmd_b)] = cmd_b
        root = re.Directory()
        for name, data in sorted((inputs or {}).items()):
            self.blobs[sha(data)] = data
            root.files.add(name=name, digest=digest_of(data), is_executable=False)
        root_b = root.SerializeToString()
        self.blobs[sha(root_b)] = root_b
        action = re.Action(command_digest=digest_of(cmd_b), input_root_digest=digest_of(root_b),
                           do_not_cache=do_not_cache, salt=salt, platform=plat)
        if timeout_s:
            action.timeout.CopyFrom(duration_pb2.Duration(seconds=timeout_s))
        act_b = action.SerializeToString()
        self.blobs[sha(act_b)] = act_b
        self.digest = digest_of(act_b)


def fingerprint(ar):
    """Stable identity of an ActionResult's *content* (not its metadata)."""
    files = sorted((f.path, f.digest.hash, f.digest.size_bytes, f.is_executable) for f in ar.output_files)
    return sha(json.dumps({"exit": ar.exit_code, "files": files,
                           "stdout": ar.stdout_digest.hash, "stderr": ar.stderr_digest.hash},
                          sort_keys=True).encode())[:16]


# --------------------------------------------------------------------------- #
# Execution engine with restart survival + event log
# --------------------------------------------------------------------------- #
class Executor:
    def __init__(self, client, events_path, deadline_s, expect_state_loss):
        self.c = client
        self.deadline_s = deadline_s
        self.expect_state_loss = expect_state_loss
        self.events = open(events_path, "a", buffering=1)
        self.lock = threading.Lock()
        self.op_results = collections.defaultdict(set)      # S2: op name -> fingerprints
        self.action_results = collections.defaultdict(set)  # S3: action hash -> fingerprints
        self.findings = []
        self.counts = collections.Counter()
        self.state_lost = []

    def log(self, **ev):
        ev["t"] = round(time.time(), 3)
        with self.lock:
            self.events.write(json.dumps(ev, separators=(",", ":")) + "\n")

    def finding(self, sig, msg, **ev):
        # A caller's own "message" (e.g. the server's status text) must not
        # collide with the finding's message.
        if "message" in ev:
            ev["detail"] = ev.pop("message")
        with self.lock:
            self.findings.append({"signature": sig, "message": msg, **ev})
        self.log(event="finding", signature=sig, message=msg, **ev)

    def _consume(self, call, rid, spec, op_name):
        """Drain an Execute/WaitExecution stream. Returns ('done', op) or raises."""
        for op in call:
            if op.name:
                if op_name[0] and op.name != op_name[0]:
                    self.log(event="op-renamed", rid=rid, old=op_name[0], new=op.name)
                op_name[0] = op.name
            if op.done:
                return op
        return None

    def _record_done(self, rid, spec, op, via):
        """Validate a done operation (S1 well-formedness, S2, S3, S4)."""
        name = op.name
        which = op.WhichOneof("result")
        if which == "error":
            code = op.error.code
            self.log(event="done-error", rid=rid, kind=spec.kind, op=name, code=code, via=via,
                     msg=op.error.message[:200])
            if not 0 <= code <= 16:
                self.finding("S1-malformed-op-error", "done operation carries out-of-range status",
                             rid=rid, op=name, code=code)
            return ("error", code)
        if which != "response":
            self.finding("S1-done-without-result", "operation done=true but no response/error",
                         rid=rid, op=name, via=via)
            return ("malformed", None)
        resp = re.ExecuteResponse()
        if not op.response.Unpack(resp):
            self.finding("S1-malformed-response", "done response is not an ExecuteResponse",
                         rid=rid, op=name, type_url=op.response.type_url)
            return ("malformed", None)
        code = resp.status.code
        fp = fingerprint(resp.result) if code == 0 else f"status-{code}"
        self.log(event="done", rid=rid, kind=spec.kind, op=name, action=spec.digest.hash[:16],
                 status=code, exit=resp.result.exit_code, cached=resp.cached_result, fp=fp, via=via)
        if not 0 <= code <= 16:
            self.finding("S1-malformed-response-status", "ExecuteResponse.status out of range",
                         rid=rid, op=name, code=code)
        with self.lock:
            self.op_results[name].add(fp)
            s2 = len(self.op_results[name]) > 1
            if code == 0:
                self.action_results[spec.digest.hash].add(fp)
                s3 = len(self.action_results[spec.digest.hash]) > 1
            else:
                s3 = False
        if s2:
            self.finding("S2-op-completed-twice-different", "operation reported done with two different results",
                         rid=rid, op=name, fingerprints=sorted(self.op_results[name]))
        if s3:
            self.finding("S3-action-nondeterministic-result",
                         "same action digest completed OK with different results",
                         rid=rid, action=spec.digest.hash, fingerprints=sorted(self.action_results[spec.digest.hash]))
        # S4: expected outcome for the action kind.
        if spec.expect == "ok" and (code != 0 or resp.result.exit_code != 0):
            self.finding("S4-unexpected-failure", "deterministic action did not exit 0 with status OK",
                         rid=rid, kind=spec.kind, op=name, status=code, exit=resp.result.exit_code,
                         message=resp.status.message[:300])
        if spec.expect == "timeout" and code == 0 and resp.result.exit_code == 0:
            self.finding("S4-timeout-not-enforced", "action exceeded Action.timeout but succeeded",
                         rid=rid, kind=spec.kind, op=name)
        return ("ok", resp)

    def run(self, spec, rid=None, skip_cache=False, cancel_after_s=None):
        """Execute one logical request to a terminal outcome. Returns (outcome, resp_or_code)."""
        rid = rid or uuid.uuid4().hex[:12]
        self.c.upload(spec.blobs)
        end = time.monotonic() + self.deadline_s
        op_name = [None]
        attempt = 0
        resume = False
        while True:
            attempt += 1
            remaining = end - time.monotonic()
            if remaining <= 0:
                self.finding("S1-no-terminal-before-deadline", "request never reached a terminal state",
                             rid=rid, kind=spec.kind, op=op_name[0], attempts=attempt - 1,
                             deadline_s=self.deadline_s)
                self.counts["stuck"] += 1
                return ("stuck", None)
            if resume and op_name[0]:
                via = "wait"
                call = self.c.wait(re.WaitExecutionRequest(name=op_name[0]), timeout=remaining)
            else:
                via = "execute"
                call = self.c.execute(re.ExecuteRequest(
                    instance_name=INSTANCE, action_digest=spec.digest, skip_cache_lookup=skip_cache,
                    digest_function=re.DigestFunction.SHA256), timeout=remaining)
            timer = None
            if cancel_after_s is not None and attempt == 1:
                timer = threading.Timer(cancel_after_s, call.cancel)
                timer.start()
            try:
                op = self._consume(call, rid, spec, op_name)
                if op is None:
                    # Stream closed with OK but never sent done=true: per REAPI
                    # the client must WaitExecution; a correct server should not
                    # do this unless it is going away.
                    self.log(event="stream-ended-not-done", rid=rid, op=op_name[0], via=via)
                    self.counts["stream_ended_not_done"] += 1
                    resume = True
                    time.sleep(0.5)
                    continue
                outcome = self._record_done(rid, spec, op, via)
                self.counts[f"done_{outcome[0]}"] += 1
                return outcome
            except grpc.RpcError as e:
                code = e.code()
                if code == grpc.StatusCode.CANCELLED and cancel_after_s is not None and attempt == 1:
                    self.log(event="client-cancelled", rid=rid, kind=spec.kind, op=op_name[0])
                    self.counts["client_cancelled"] += 1
                    return ("cancelled", None)
                if via == "wait" and code in (grpc.StatusCode.NOT_FOUND, grpc.StatusCode.INVALID_ARGUMENT,
                                              grpc.StatusCode.FAILED_PRECONDITION):
                    # The scheduler forgot an operation it had acknowledged.
                    self.state_lost.append({"rid": rid, "op": op_name[0], "code": code.name})
                    self.counts["state_lost"] += 1
                    self.log(event="state-lost", rid=rid, kind=spec.kind, op=op_name[0], code=code.name,
                             details=(e.details() or "")[:200])
                    if not self.expect_state_loss:
                        self.finding("S5-operation-state-lost", "acknowledged operation unknown after restart",
                                     rid=rid, op=op_name[0], code=code.name)
                    op_name[0], resume = None, False
                    continue
                if code == grpc.StatusCode.DEADLINE_EXCEEDED and time.monotonic() >= end - 1:
                    continue  # our own overall deadline: the loop head records S1
                if code in RETRYABLE:
                    self.counts[f"retry_{code.name}"] += 1
                    self.log(event="transport-error", rid=rid, op=op_name[0], via=via, code=code.name,
                             details=(e.details() or "")[:200])
                    resume = op_name[0] is not None
                    time.sleep(min(0.25 * attempt, 3.0))
                    continue
                if code in TERMINAL_ERRORS:
                    self.log(event="terminal-error", rid=rid, kind=spec.kind, op=op_name[0], code=code.name,
                             details=(e.details() or "")[:300])
                    self.counts[f"terminal_{code.name}"] += 1
                    if spec.expect == "ok":
                        self.finding("S4-unexpected-failure", "deterministic action failed with a gRPC error",
                                     rid=rid, kind=spec.kind, code=code.name, details=(e.details() or "")[:300])
                    return ("error", code.name)
                self.finding("S1-malformed-status", "Execute failed with an unexpected status",
                             rid=rid, code=code.name, details=(e.details() or "")[:300])
                return ("error", code.name)
            finally:
                if timer:
                    timer.cancel()
                call.cancel()

    def summary(self):
        return {"counts": dict(self.counts), "findings": self.findings,
                "state_lost": len(self.state_lost),
                "state_lost_expected": self.expect_state_loss,
                "distinct_ops_done": len(self.op_results),
                "distinct_actions_ok": len(self.action_results)}


# --------------------------------------------------------------------------- #
# Workloads
# --------------------------------------------------------------------------- #
def build_specs_layer1(salt, path_env, n=16):
    specs = []
    for i in range(n):
        script = (f"mkdir -p gen && i=0; while [ $i -lt {200 + 37 * i} ]; do "
                  f"echo \"gen{i} line $i $((i * {i + 3} % 97))\"; i=$((i+1)); done > gen/g{i:02d}.txt")
        specs.append(ActionSpec("build-gen", script, salt=salt, outputs=[f"gen/g{i:02d}.txt"], path_env=path_env))
    return specs


def cmd_build(args, ex, client, path_env):
    out = pathlib.Path(args.out)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    salt = args.salt.encode()
    produced = {}

    def run_layer(specs):
        with cf.ThreadPoolExecutor(max_workers=8) as pool:
            res = list(pool.map(lambda s: ex.run(s, skip_cache=args.skip_cache), specs))
        layer = {}
        for s, (kind, resp) in zip(specs, res):
            if kind != "ok" or resp.status.code != 0 or resp.result.exit_code != 0:
                raise SystemExit(f"build step {s.kind} failed: {kind}")
            for f in resp.result.output_files:
                data = client.fetch(f.digest)
                p = out / f.path
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_bytes(data)
                p.chmod(0o755 if f.is_executable else 0o644)
                layer[f.path] = data
        return layer

    gen = run_layer(build_specs_layer1(salt, path_env))
    produced.update(gen)
    names = sorted(gen)
    comb_specs = []
    for j in range(4):
        group = {pathlib.Path(n).name: gen[n] for n in names[j * 4:(j + 1) * 4]}
        script = (f"mkdir -p comb && cat {' '.join(sorted(group))} | sort | uniq -c | sort -k2 > comb/c{j}.txt "
                  f"&& sha256sum {' '.join(sorted(group))} >> comb/c{j}.txt")
        comb_specs.append(ActionSpec("build-comb", script, inputs=group, salt=salt,
                                     outputs=[f"comb/c{j}.txt"], path_env=path_env))
    comb = run_layer(comb_specs)
    produced.update(comb)
    link_inputs = {pathlib.Path(n).name: d for n, d in comb.items()}
    script = ("mkdir -p final && sha256sum c0.txt c1.txt c2.txt c3.txt > final/manifest.txt && "
              "cat c0.txt c1.txt c2.txt c3.txt | wc -l > final/lines.txt && "
              "printf '#!/bin/sh\\necho linked\\n' > final/tool.sh && chmod +x final/tool.sh")
    link = run_layer([ActionSpec("build-link", script, inputs=link_inputs, salt=salt,
                                 outputs=["final/manifest.txt", "final/lines.txt", "final/tool.sh"],
                                 path_env=path_env)])
    produced.update(link)
    print(f"build: {len(produced)} outputs written to {out}", flush=True)


def cmd_stress(args, ex, client, path_env):
    rng = random.Random(f"stress:{args.seed}")
    pool_specs = [ActionSpec("cacheable", f"echo cacheable-{k}; printf 'k={k}\\n' > out.txt",
                             salt=f"pool:{args.seed}".encode(), outputs=["out.txt"], path_env=path_env)
                  for k in range(6)]
    stop = time.monotonic() + args.seconds
    n = 0
    futures = []
    with cf.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        while time.monotonic() < stop:
            n += 1
            scenario = rng.choices(["cacheable", "no-cache", "dup", "sleep-cancel", "sleep-ok", "timeout"],
                                   weights=[3, 3, 2, 1, 1, 1])[0]
            salt = f"{args.seed}:{n}".encode()
            if scenario == "cacheable":
                futures.append(pool.submit(ex.run, rng.choice(pool_specs)))
            elif scenario == "no-cache":
                s = ActionSpec("no-cache", f"echo nocache-{n}", do_not_cache=True, salt=salt, path_env=path_env)
                futures.append(pool.submit(ex.run, s, None, True))
            elif scenario == "dup":
                # Concurrent identical actions: the scheduler should dedup to one
                # execution and every waiter must see the same result.
                s = ActionSpec("dup", f"sleep 0.{rng.randint(2, 9)}; echo dup-{n} > d.txt",
                               salt=salt, outputs=["d.txt"], path_env=path_env)
                for _ in range(rng.randint(3, 8)):
                    futures.append(pool.submit(ex.run, s, None, True))
            elif scenario == "sleep-cancel":
                s = ActionSpec("sleep-cancel", f"sleep {rng.randint(3, 8)}; echo slept", do_not_cache=True,
                               salt=salt, expect="any", path_env=path_env)
                futures.append(pool.submit(ex.run, s, None, True, rng.uniform(0.5, 2.5)))
            elif scenario == "sleep-ok":
                s = ActionSpec("sleep-ok", f"sleep {rng.randint(1, 4)}; echo slept > s.txt", salt=salt,
                               outputs=["s.txt"], path_env=path_env)
                futures.append(pool.submit(ex.run, s, None, True))
            else:
                s = ActionSpec("timeout", "sleep 30; echo late", do_not_cache=True, timeout_s=2,
                               salt=salt, expect="timeout", path_env=path_env)
                futures.append(pool.submit(ex.run, s, None, True))
            # Keep the queue bounded so new submissions track wall time.
            while sum(not f.done() for f in futures) >= args.concurrency * 2 and time.monotonic() < stop:
                time.sleep(0.05)
            time.sleep(rng.uniform(0.0, 0.15))
        for f in futures:
            try:
                f.result()
            except Exception as e:  # an iteration that crashes is itself a finding
                ex.finding("harness-exception", f"{type(e).__name__}: {e}")
    print(f"stress: {len(futures)} requests from {n} scenarios", flush=True)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", choices=["build", "stress"])
    p.add_argument("--target", required=True, help="host:port (normally the rechaos gateway)")
    p.add_argument("--report", required=True, help="summary JSON path")
    p.add_argument("--events", help="event log JSONL (default: REPORT with .events.jsonl)")
    p.add_argument("--deadline", type=float, default=180, help="per-request terminal deadline, seconds")
    p.add_argument("--expect-state-loss", action="store_true",
                   help="scheduler restarts lose state by design (memory backend): S5 is baseline, not a finding")
    p.add_argument("--path-env", default=os.pathsep.join(sorted({os.path.dirname(shutil.which(b) or "/bin/x")
                                                                 for b in ("sh", "sleep", "sha256sum", "sort")})),
                   help="PATH given to remote commands (part of the action digest)")
    p.add_argument("--out", help="build: output tree directory")
    p.add_argument("--salt", default="clean", help="build: Action.salt (forces fresh execution per pass)")
    p.add_argument("--skip-cache", action="store_true", help="build: set skip_cache_lookup")
    p.add_argument("--seed", type=int, default=1, help="stress: RNG seed")
    p.add_argument("--seconds", type=float, default=60, help="stress: duration")
    p.add_argument("--concurrency", type=int, default=12, help="stress: concurrent requests")
    args = p.parse_args()
    client = Client(args.target)
    grpc.channel_ready_future(client.ch).result(timeout=30)
    ex = Executor(client, args.events or args.report.replace(".json", "") + ".events.jsonl",
                  args.deadline, args.expect_state_loss)
    t0 = time.monotonic()
    rc = 0
    try:
        if args.command == "build":
            if not args.out:
                p.error("build needs --out")
            cmd_build(args, ex, client, args.path_env)
        else:
            cmd_stress(args, ex, client, args.path_env)
    except SystemExit as e:
        ex.finding("build-failed", str(e))
        rc = 1
    summary = {"command": args.command, "seconds": round(time.monotonic() - t0, 1), **ex.summary()}
    pathlib.Path(args.report).write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({k: v for k, v in summary.items() if k != "findings"}), flush=True)
    sigs = collections.Counter(f["signature"] for f in ex.findings)
    if sigs:
        print(f"FINDINGS: {dict(sigs)}", flush=True)
    sys.exit(1 if ex.findings or rc else 0)


if __name__ == "__main__":
    main()
