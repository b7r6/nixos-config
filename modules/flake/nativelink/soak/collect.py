#!/usr/bin/env python3
# Vendored 2026-10-13 from ~/src/b7r6/rechaos-nativelink-raft (no remote; rev
# 1b9c1606b43c8a65d9163e27d8c9f52900740eec) for the Azure soak rig. Byte-identical
# to the harness copy; keep it that way and upstream fixes there.
"""Fold every finding source of one run into findings/all.jsonl + summary.json.

Sources: chaos-monkey findings.jsonl per seed (monkey/*/findings.jsonl), workload
reports (workload/*.json, each with a "findings" list), the output oracle exit
code, and restart-chaos's restart.json. Items that are EXPECTED for the backend
(memory: scheduler state lost on restart) are listed under "baseline" and do not
count as findings. Exit 1 if any finding, else 0.
"""
import argparse
import collections
import json
import pathlib
import sys


def main():
    p = argparse.ArgumentParser()
    p.add_argument("run_dir")
    a = p.parse_args()
    run = pathlib.Path(a.run_dir)
    manifest = json.loads((run / "manifest.json").read_text())
    findings, baseline, sources = [], {}, {}

    for fl in sorted(run.glob("monkey/*/findings.jsonl")):
        seed = fl.parent.name
        items = [json.loads(line) for line in fl.read_text().splitlines() if line.strip()]
        for it in items:
            findings.append({"source": f"monkey:{seed}", "signature": it["signature"],
                             "detail": it.get("kind"), "evidence": it.get("evidence")})
        summ = fl.parent / "summary.json"
        if summ.exists():
            s = json.loads(summ.read_text())
            sources[f"monkey:{seed}"] = {"iterations": s.get("iterations"), "findings": s.get("findings_total"),
                                         "signatures": s.get("signatures")}

    for rep in sorted(run.glob("workload/*.json")):
        if rep.name.startswith("oracle-"):
            continue
        try:
            r = json.loads(rep.read_text())
        except json.JSONDecodeError:
            findings.append({"source": f"workload:{rep.stem}", "signature": "report-unreadable"})
            continue
        if not isinstance(r, dict):
            continue
        sources[f"workload:{rep.stem}"] = {k: r.get(k) for k in ("counts", "state_lost", "seconds",
                                                                 "distinct_ops_done", "distinct_actions_ok")}
        for f in r.get("findings", []):
            findings.append({"source": f"workload:{rep.stem}", **f})
        if r.get("state_lost") and r.get("state_lost_expected"):
            baseline[f"S5-operation-state-lost ({rep.stem})"] = r["state_lost"]
        for k, v in (r.get("baseline") or {}).items():
            baseline[k] = v

    # Each `rechaos oracle` run leaves workload/oracle-NAME.rc (exit code) and
    # workload/oracle-NAME.json (its stdout verdict).
    for rcf in sorted(run.glob("workload/oracle-*.rc")):
        name = rcf.stem
        rc = int(rcf.read_text().strip() or 99)
        verdict = {0: "equivalent", 1: "diverged", 2: "inconclusive"}.get(rc, f"exit-{rc}")
        sources[name] = verdict
        if rc != 0:
            ev = rcf.with_suffix(".json")
            findings.append({"source": name, "signature": f"oracle-{verdict}",
                             "detail": "clean and chaos output trees differ (or could not be compared)",
                             "evidence": ev.read_text()[:2000] if ev.exists() else None})

    fdir = run / "findings"
    fdir.mkdir(exist_ok=True)
    with (fdir / "all.jsonl").open("w") as fh:
        for f in findings:
            fh.write(json.dumps(f, separators=(",", ":")) + "\n")
    sigs = collections.Counter(f"{f['source'].split(':')[0]}:{f['signature']}" for f in findings)
    summary = {"backend": manifest["backend"], "kind": manifest["kind"], "run_dir": str(run),
               "findings_total": len(findings), "unique_signatures": dict(sigs.most_common()),
               "expected_baseline_differences": baseline, "sources": sources}
    (run / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({k: summary[k] for k in ("findings_total", "unique_signatures",
                                              "expected_baseline_differences")}, indent=2))
    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()
