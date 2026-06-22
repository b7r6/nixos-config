# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                          // hyper-modern-nixos // clickhouse-keeper-smoke-test
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# A self-contained ZooKeeper-protocol smoke test for a ClickHouse Keeper node,
# used as a post-start health gate (systemd oneshot) and as the assertion engine
# behind the NixOS check. Adapted from the straylight-infra prior art
# (nix/packages/clickhouse-keeper-smoke-test), with two corrections for our
# split (server-less) Keeper topology:
#
#   - it dials the KEEPER client port (9181, the ZK protocol), not the
#     clickhouse-native 9000 — our Keeper nodes run NO co-located clickhouse, so
#     9000 isn't even listening here. (straylight's default port = 9000 worked
#     only because it co-located a server.)
#   - it adds a four-letter-word health probe (ruok/mntr) so the resilience
#     drills can read quorum/leader state, not just CRUD success.
{ writers, python3Packages, ... }:
# writePython3Bin's built-in flake8 wants PEP8 4-space indentation, but the
# repo's house style (ruff.toml) is 2-space. We follow the repo: ignore the
# indentation-width checks (E111/E114/E117/E121) and long-line (E501); the code
# is still ruff-clean.
writers.writePython3Bin "clickhouse-keeper-smoke-test" {
  libraries = with python3Packages; [ kazoo ];
  flakeIgnore = [
    "E111"
    "E114"
    "E117"
    "E121"
    "E501"
  ];
} (builtins.readFile ./clickhouse-keeper-smoke-test.py)
