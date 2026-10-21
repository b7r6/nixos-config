# railgun — the NativeLink console (ORBITAL // NATIVELINK) at nativelink.s4.gl.
#
# A static Halogen app (repo straylight/orbital-nativelink on git.s4.gl; the
# working checkout is /home/b7r6/src/hypermodern/orbital-nativelink) over three
# same-origin, read-only data paths:
#
#   /ch/    → ClickHouse HTTP (127.0.0.1:8123) as the `console` user: readonly
#             profile, SELECT on otel.* only, loopback-only (nginx is the sole
#             caller; the host firewall keeps 8123 off every other interface).
#   /nix/   → the NativeLink nix_cache HTTP API (127.0.0.1:50071): nix-cache-info,
#             <hash>.narinfo, log/<drv>.
#   /api/   → JSON written every 15 s by the `nativelink-console-probe` timer:
#             services.json (units + listeners + NixOS generations) and
#             store.json (newest store paths, for the inspector's suggestions).
#             Nothing executes per request; nginx serves files.
#
# The bundle is built ON railgun by `nativelink-ui-build` (spago fetches the
# package registry at build time, so it is not a pure derivation yet).
{ config, flake, pkgs, lib, ... }:
let
  webRoot = "/var/www/nativelink";
  apiDir = "/var/lib/nativelink-console";
  srcDir = "/home/b7r6/src/hypermodern/orbital-nativelink";
  # hydrogen (the Orbital design system) comes from the same monorepo input the
  # forge is built from; spago.yaml points at ../hydrogen.
  projectsDir = "${flake.inputs.orbital-forge}/..";

  units =
    # split (fleet.dhall layout): one unit per process under nativelink.target
    map (p: "nativelink-${p}.service") config.hyper-modern-nixos.nativelink.split.processes
    ++ [
    "nativelink-nix-cache.service"
    "nativelink-nix-cache-watch.service"
    "nativelink-nix-cache-reconcile.timer"
    "clickhouse.service"
    "clickhouse-keeper.service"
    "opentelemetry-collector.service"
    "grafana.service"
    "nginx.service"
    "postgresql.service"
    "forgejo.service"
    "coredns.service"
    "tailscaled.service"
  ];
  listeners = [
    { name = "scheduler / REAPI"; port = 50051; }
    { name = "CAS"; port = 50052; }
    { name = "worker API"; port = 50061; }
    { name = "nix cache"; port = 50071; }
    { name = "ClickHouse HTTP"; port = 8123; }
    { name = "ClickHouse native"; port = 9000; }
    { name = "Keeper"; port = 9181; }
    { name = "OTLP gRPC"; port = 4317; }
    { name = "Grafana"; port = 3300; }
    { name = "nginx"; port = 443; }
  ];

  probe = pkgs.writeShellApplication {
    name = "nativelink-console-probe";
    runtimeInputs = with pkgs; [ systemd iproute2 jq coreutils findutils gnugrep gawk gnused nix ];
    text = ''
      set -euo pipefail
      out=${apiDir}
      mkdir -p "$out"
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

      units_json=$(for u in ${lib.concatStringsSep " " units}; do
        systemctl show "$u" -p Id,ActiveState,SubState,NRestarts,ActiveEnterTimestamp,Description 2>/dev/null \
          | jq -R 'select(contains("=")) | split("=") | {key: .[0], value: (.[1:] | join("="))}' | jq -s 'from_entries'
      done | jq -s '.')

      ss_ports=$(ss -ltnH 2>/dev/null | awk '{print $4}' | sed 's/.*://' | sort -u)
      listeners_json=$(for spec in ${lib.concatMapStringsSep " " (l: ''"${l.name}|${toString l.port}"'') listeners}; do
        name=''${spec%|*}; port=''${spec##*|}
        if grep -qx "$port" <<<"$ss_ports"; then up=true; else up=false; fi
        jq -n --arg name "$name" --argjson port "$port" --argjson up "$up" '{name:$name, port:$port, listening:$up}'
      done | jq -s '.')

      gens_json=$(nix-env -p /nix/var/nix/profiles/system --list-generations 2>/dev/null \
        | tail -n 12 | jq -R -s 'split("\n") | map(select(length>0) | capture("^\\s*(?<id>[0-9]+)\\s+(?<date>\\S+ \\S+)\\s*(?<current>\\(current\\))?")) | map({id: (.id|tonumber), date, current: (.current != null)})' \
        || echo '[]')

      current=$(readlink -f /run/current-system)
      jq -n --arg now "$now" --arg host "$(uname -n)" --arg current "$current" \
        --arg kernel "$(uname -r)" --arg uptime "$(cut -d' ' -f1 /proc/uptime)" \
        --argjson units "$units_json" --argjson listeners "$listeners_json" --argjson generations "$gens_json" \
        '{generatedAt:$now, host:$host, currentSystem:$current, kernel:$kernel, uptimeSeconds:($uptime|tonumber), units:$units, listeners:$listeners, generations:$generations}' \
        > "$out/services.json.tmp" && mv "$out/services.json.tmp" "$out/services.json"

      # newest store paths (no .drv/.lock), for the inspector's suggestions.
      # Store paths carry mtime 1 (the epoch); registration time is the ctime.
      find /nix/store -maxdepth 1 -mindepth 1 -newerct '-7 days' \
        -not -name '*.drv' -not -name '*.lock' -not -name '.links' -printf '%C@ %f\n' 2>/dev/null \
        | grep -E ' [0-9a-z]{32}-' | sort -rn | awk 'NR <= 400 { print $2 }' \
        | jq -R -s --arg now "$now" '{generatedAt:$now, paths: (split("\n") | map(select(length>0)))}' \
        > "$out/store.json.tmp" && mv "$out/store.json.tmp" "$out/store.json"
    '';
  };

  uiBuild = pkgs.writeShellApplication {
    name = "nativelink-ui-build";
    runtimeInputs = with pkgs; [ nodejs_24 purescript esbuild git rsync coreutils ];
    text = ''
      set -euo pipefail
      src="''${1:-${srcDir}}"
      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      mkdir -p "$work/projects"
      cp -r ${projectsDir}/hydrogen "$work/projects/hydrogen"
      rsync -a --exclude node_modules --exclude .spago --exclude output --exclude dist "$src"/ "$work/projects/orbital-nativelink/"
      chmod -R u+w "$work"
      cd "$work/projects/orbital-nativelink"
      export HOME="$work/home"; mkdir -p "$HOME"
      npm ci --no-audit --no-fund
      npm run build
      sudo install -d -m 755 ${webRoot}
      sudo rsync -a --delete dist/ ${webRoot}/
      sudo chown -R root:root ${webRoot}
      echo "nativelink console installed to ${webRoot}"
    '';
  };
in
{
  # ── ClickHouse: the console's read-only identity ───────────────────────────
  environment.etc."clickhouse-server/users.d/console.xml".text = ''
    <clickhouse>
      <profiles>
        <console_reader>
          <readonly>2</readonly>
          <max_execution_time>20</max_execution_time>
          <max_result_rows>20000</max_result_rows>
          <result_overflow_mode>break</result_overflow_mode>
          <allow_deprecated_error_prone_window_functions>1</allow_deprecated_error_prone_window_functions>
        </console_reader>
      </profiles>
      <users>
        <console>
          <no_password/>
          <networks>
            <ip>127.0.0.1</ip>
            <ip>::1</ip>
          </networks>
          <profile>console_reader</profile>
          <quota>default</quota>
          <grants>
            <query>GRANT SELECT ON otel.*</query>
          </grants>
        </console>
      </users>
    </clickhouse>
  '';

  # ── nginx: the vhost is the reverseProxy's (root = webRoot, ./default.nix);
  # these same-origin data locations merge into it. ────────────────────────────
  services.nginx.virtualHosts."nativelink.s4.gl".locations = {
    "/ch/" = {
      proxyPass = "http://127.0.0.1:8123/";
      extraConfig = ''
        limit_except GET POST { deny all; }
        proxy_set_header X-ClickHouse-User console;
        proxy_set_header X-ClickHouse-Key "";
        proxy_buffering off;
        proxy_read_timeout 30s;
        add_header Cache-Control "no-store";
      '';
    };
    "/nix/" = {
      proxyPass = "http://127.0.0.1:50071/nix/";
      extraConfig = ''
        limit_except GET HEAD { deny all; }
        proxy_buffering off;
        add_header Cache-Control "no-store";
      '';
    };
    "/api/" = {
      alias = "${apiDir}/";
      extraConfig = ''
        default_type application/json;
        add_header Cache-Control "no-store";
      '';
    };
    "/".extraConfig = lib.mkAfter "try_files $uri $uri/ /index.html;";
  };

  # ── the probe: facts nginx can serve as files ──────────────────────────────
  systemd.services.nativelink-console-probe = {
    description = "NativeLink console probe (units, listeners, generations, store sample → JSON)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${probe}/bin/nativelink-console-probe";
      StateDirectory = "nativelink-console";
    };
  };
  systemd.timers.nativelink-console-probe = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "20s";
      OnUnitActiveSec = "15s";
      AccuracySec = "2s";
    };
  };

  systemd.tmpfiles.rules = [
    "d ${webRoot} 0755 root root -"
    "d ${apiDir} 0755 root root -"
  ];

  environment.systemPackages = [
    uiBuild
    probe
    pkgs.grpcurl
  ];
}
