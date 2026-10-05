"""ClickHouse Keeper smoke test.

Connects to a Keeper node over the ZooKeeper protocol (client port, default
9181), runs a CRUD round-trip on a throwaway znode, and reports the node's
four-letter-word health (ruok / mntr). Exits non-zero on any failure so it can
gate a systemd oneshot and drive the NixOS resilience check.
"""

import argparse
import logging
import socket
import sys
import time

from kazoo.client import KazooClient, KazooState


log = logging.getLogger("keeper-smoke")

TEST_PATH = "/hyper_modern_keeper_smoke"
TEST_DATA = b"smoke"


def four_letter_word(host, port, word, timeout=5.0):
  """Send a Keeper/ZooKeeper four-letter-word command and return the reply."""
  with socket.create_connection((host, port), timeout=timeout) as sock:
    sock.sendall(word.encode("ascii"))
    chunks = []
    while True:
      buf = sock.recv(4096)
      if not buf:
        break
      chunks.append(buf)
  return b"".join(chunks).decode("utf-8", errors="replace")


def run_crud_ops(zk):
  """Create / read / update / delete a throwaway znode."""
  # Start from a clean slate (a prior failed run may have left the node).
  if zk.exists(TEST_PATH):
    zk.delete(TEST_PATH, recursive=True)

  zk.create(TEST_PATH, b"init")
  if not zk.exists(TEST_PATH):
    log.critical("CRUD: test path does not exist after create")
    sys.exit(1)

  zk.set(TEST_PATH, TEST_DATA)
  data, _ = zk.get(TEST_PATH)
  if data != TEST_DATA:
    log.critical("CRUD: read-back mismatch: %r != %r", data, TEST_DATA)
    sys.exit(1)

  zk.delete(TEST_PATH, recursive=True)
  if zk.exists(TEST_PATH):
    log.critical("CRUD: test path still exists after delete")
    sys.exit(1)

  log.info("CRUD: create/read/update/delete round-trip OK")


def on_state(state):
  if state == KazooState.LOST:
    log.error("keeper connection lost")
  elif state == KazooState.SUSPENDED:
    log.warning("keeper connection suspended")


def main():
  logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

  parser = argparse.ArgumentParser(
    prog="clickhouse-keeper-smoke-test",
    description="ZooKeeper-protocol smoke test for a ClickHouse Keeper node",
  )
  parser.add_argument("-H", "--host", default="127.0.0.1")
  parser.add_argument(
    "-p", "--port", type=int, default=9181, help="Keeper client (ZooKeeper protocol) port"
  )
  parser.add_argument(
    "--wait",
    type=float,
    default=0.0,
    metavar="SECONDS",
    help="Keep retrying the initial ruok for up to this long before failing. "
    "Keeper's unit reports started before the client port listens, so a "
    "post-start gate needs a grace window at boot.",
  )
  parser.add_argument(
    "--server-state",
    action="store_true",
    help="Print only this node's Raft role (leader/follower/...) from mntr and exit.",
  )
  args = parser.parse_args()

  # --server-state: print zk_server_state and exit (no session/CRUD). Used by the
  # NixOS check to assert exactly one leader without depending on a netcat dialect.
  if args.server_state:
    mntr = four_letter_word(args.host, args.port, "mntr")
    for line in mntr.splitlines():
      if line.startswith("zk_server_state"):
        print(line.split()[1])
        return
    log.critical("server-state: zk_server_state not found in mntr output")
    sys.exit(1)

  # ruok must answer 'imok' before we bother with a session. Within the
  # --wait window a refused/timed-out connection is a retry, not a failure.
  deadline = time.monotonic() + args.wait
  while True:
    try:
      ruok = four_letter_word(args.host, args.port, "ruok").strip()
      break
    except OSError as exc:
      if time.monotonic() < deadline:
        log.info("ruok: %s:%d not up yet (%s), retrying", args.host, args.port, exc)
        time.sleep(2)
        continue
      log.critical("ruok: cannot reach %s:%d (%s)", args.host, args.port, exc)
      sys.exit(1)
  if ruok != "imok":
    log.critical("ruok: expected 'imok', got %r", ruok)
    sys.exit(1)
  log.info("ruok: imok")

  # mntr is informational (leader/follower, znode count, etc.) -- log it.
  try:
    mntr = four_letter_word(args.host, args.port, "mntr")
    for line in mntr.splitlines():
      if line.strip():
        log.info("mntr %s", line.strip())
  except OSError as exc:
    log.warning("mntr: %s", exc)

  zk = KazooClient(hosts=f"{args.host}:{args.port}")
  zk.add_listener(on_state)
  zk.start(timeout=15)
  try:
    run_crud_ops(zk)
  finally:
    zk.stop()
    zk.close()

  log.info("keeper smoke test PASSED (%s:%d)", args.host, args.port)


if __name__ == "__main__":
  main()
