# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                         // hyper-modern-nixos // checks // grafana-dashboards
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Renders EVERY dashboard in modules/flake/grafana/dashboards/ through
# dhall-to-json — the same transform watchtower's provisioning runs at system
# build. Until now a type error in a dashboard only surfaced when watchtower
# itself was rebuilt; this makes the whole dhall surface a repo-wide gate.
# Each output must also be a JSON object with the fields grafana's provider
# actually requires (title, uid, panels).
{ pkgs }:
pkgs.runCommand "grafana-dashboards"
  {
    nativeBuildInputs = [
      pkgs.dhall-json
      pkgs.jq
    ];
  }
  ''
    mkdir -p $out
    fail=0
    for f in ${../modules/flake/grafana}/dashboards/*.dhall; do
      name=$(basename "$f" .dhall)
      echo "── rendering $name"
      if ! dhall-to-json --file "$f" > "$out/$name.json"; then
        echo "FAIL: $name does not render"; fail=1; continue
      fi
      if ! jq -e 'has("title") and has("uid") and has("panels")' \
          "$out/$name.json" > /dev/null; then
        echo "FAIL: $name missing title/uid/panels"; fail=1
      fi
    done
    exit $fail
  ''
