# railgun — Grafana: the wall.
#
# Two dashboard sets, provisioned from the store, foldered by directory:
#   NativeLink/  hypermodern-nativelink's typed Dhall set (nativelink,
#                projector, soak-runs, differential, inference) — the flake's
#                telemetry contract and its dashboards move together.
#   Fleet/       nixos-config's fleet set (modules/flake/grafana/dashboards):
#                overview, host drill-down, service health, ClickHouse +
#                Keeper internals, CoreDNS, log explorer, topology, Wintermute,
#                Forgejo (live again once ./forge.nix lands).
#   Retired/     dashboards for services the sold fleet ran (Attic, Zot,
#                Kanidm, Supabase, PITR, exit rotation): kept as history.
# nixos-config's own nativelink.dhall shares uid `nativelink` with the flake's
# and is the older copy, so it is NOT provisioned here.
#
# Datasource: this host's ClickHouse over loopback (otel.*), uid `clickhouse`
# as every dashboard expects. Loopback only; nginx fronts it at grafana.s4.gl.
{
  config,
  flake,
  lib,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  nativelinkDashboards = flake.inputs.hypermodern-nativelink.packages.${system}.grafana-dashboards;

  # The WHOLE grafana tree goes to the store (dashboards import ../schema and
  # ../../schema), so renders take a path RELATIVE to it.
  grafanaDir = ../../../modules/flake/grafana;
  fleetDir = grafanaDir + "/dashboards";
  renderDhall =
    name: rel:
    pkgs.runCommand "grafana-dashboard-${name}.json" { nativeBuildInputs = [ pkgs.dhall-json ]; } ''
      export HOME="$TMPDIR" XDG_CACHE_HOME="$TMPDIR/dhall-cache"
      mkdir -p "$XDG_CACHE_HOME"
      dhall-to-json --file ${grafanaDir}/dashboards/${rel} > "$out"
    '';
  # Both sets ship every row collapsed (fine in an editor, useless on a wall):
  # expand each row and hoist its nested panels to the top level; give
  # unnamed series a readable legend. Grafana's
  # layout is driven by gridPos, which collapsed panels keep, so the order is
  # preserved. Also clear `id`s so provisioning never collides on them.
  # Design pass (2026-10-18): one visual language for every provisioned board.
  #   - descriptions on every panel, keyed by dashboard + title (./grafana/descriptions.json);
  #   - stat tiles: colour means status, so plain stats are uncoloured and only
  #     thresholded ones colour their value; no sparkline, no percent-change;
  #   - series charts: quiet list legend, zero baseline, "no data in range" when empty;
  #   - shared crosshair, UTC, so the wall and the console agree on time.
  # The Dhall-rendered boards already carry most of this from the schema; the
  # upstream NativeLink board (hypermodern-nativelink) gets it here.
  descriptions = ./grafana/descriptions.json;
  dashboardFilter = pkgs.writeText "dashboard.jq" ''
    def hoist: reduce .[] as $p ([];
      if ($p.type == "row" and ($p.collapsed // false))
      then . + [($p | .collapsed = false | .panels = [])] + ($p.panels // [])
      else . + [$p] end);
    # Legends: ClickHouse frames arrive as `value {k="v", …}`; show the label
    # VALUES ("sda, read") unless the panel names its series itself.
    def legend:
      if (.type == "timeseries" or .type == "barchart" or .type == "piechart")
         and ((.fieldConfig.defaults.displayName // "") == "")
      then .fieldConfig.defaults.displayName = "''${__field.labels.__values}" else . end;
    def thresholded: ((.fieldConfig.defaults.thresholds.steps // []) | length) > 1;
    def describe: .description = ($desc[0][$name][.title] // .description // "");
    def stat:
      if .type == "stat" then
        .options.graphMode = "none" | .options.textMode = "value"
        | .options.showPercentChange = false | .options.wideLayout = true
        | .options.colorMode = (if thresholded then "value" else "none" end)
        | .fieldConfig.defaults.color.mode = (if thresholded then "thresholds" else "palette-classic" end)
        | (if (.title | test("— %$")) then .fieldConfig.defaults.unit = "percent" | .fieldConfig.defaults.decimals = 1 else . end)
      else . end;
    def series:
      if .type == "timeseries" then
        .options.legend = (if (.options.legend.showLegend // true) == false
                           then {displayMode: "list", placement: "bottom", calcs: [], showLegend: false}
                           else {displayMode: "list", placement: "bottom", calcs: [], showLegend: true} end)
        | .fieldConfig.defaults.min = (.fieldConfig.defaults.min // 0)
      else . end;
    def novalue: .fieldConfig.defaults.noValue = (.fieldConfig.defaults.noValue // "no data in range");
    def tidy: if .type == "row" then . else (describe | stat | series | novalue) end;
    .panels |= hoist | .panels |= map(legend | tidy) | .id = null
    | .graphTooltip = 1 | .timezone = "utc"
  '';
  expandRows =
    name: src:
    pkgs.runCommand "grafana-dashboard-${name}-expanded.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
      jq --arg name "${name}" --slurpfile desc ${descriptions} -f ${dashboardFilter} ${src} > "$out"
    '';
  dhallNames = dir: builtins.filter (n: builtins.match ".*\\.dhall" n != null) (builtins.attrNames (builtins.readDir dir));
  strip = n: builtins.replaceStrings [ ".dhall" ] [ "" ] n;

  # Fleet: every top-level dashboard but nativelink.dhall (uid clash, see above),
  # plus the two "retired" ones that are live on this host.
  # wintermute is the desktop shell's reconciler: nothing to show on a
  # headless host, so it joins the Retired folder here.
  headlessRetired = [ "wintermute.dhall" ];
  fleetFiles = builtins.filter (n: n != "nativelink.dhall" && !(builtins.elem n headlessRetired)) (dhallNames fleetDir);
  revived = [ "coredns.dhall" "forgejo-activity.dhall" ];
  retiredFiles = builtins.filter (n: !(builtins.elem n revived)) (dhallNames (fleetDir + "/retired"));

  fleetEtc = builtins.listToAttrs (
    map (n: { name = "grafana/dashboards/Fleet/${strip n}.json"; value.source = expandRows (strip n) (renderDhall (strip n) n); }) fleetFiles
    ++ map (n: { name = "grafana/dashboards/Fleet/${strip n}.json"; value.source = expandRows (strip n) (renderDhall (strip n) "retired/${n}"); }) revived
    ++ map (n: { name = "grafana/dashboards/Retired/${strip n}.json"; value.source = expandRows (strip n) (renderDhall (strip n) "retired/${n}"); }) retiredFiles
    ++ map (n: { name = "grafana/dashboards/Retired/${strip n}.json"; value.source = expandRows (strip n) (renderDhall (strip n) n); }) headlessRetired
  );
  # Only the NativeLink dashboard itself: projector, soak-runs, differential
  # and inference read the soak RIG's `soak.*` schema (and a peer site's
  # datasource) — they are the soak wall's, not this host's, and would only
  # render errors here.
  nativelinkEtc = {
    "grafana/dashboards/NativeLink/nativelink.json".source =
      expandRows "nativelink" "${nativelinkDashboards}/nativelink.json";
  };

  adminPasswordFile = "/run/agenix/grafana-admin-password";
in
{
  age.secrets.grafana-admin-password = {
    file = ../../../secrets/agenix/machines/grafana-admin-password.age;
    owner = "grafana";
    group = "grafana";
    mode = "0400";
  };

  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3300;
        root_url = "https://grafana.s4.gl/";
        domain = "grafana.s4.gl";
        enable_gzip = true;
      };
      security = {
        admin_user = "admin";
        admin_password = "$__file{${adminPasswordFile}}";
        secret_key = "$__file{${adminPasswordFile}}";
        cookie_secure = true;
      };
      "auth.anonymous".enabled = false;
      users = {
        default_theme = "dark";
        home_page = "/d/nativelink?kiosk";
      };
      dashboards = {
        default_home_dashboard_path = "/etc/grafana/dashboards/NativeLink/nativelink.json";
        min_refresh_interval = "5s";
        versions_to_keep = 20;
      };
      # No phoning home, no news feed, no "welcome" clutter on the wall.
      analytics = {
        reporting_enabled = false;
        check_for_updates = false;
        check_for_plugin_updates = false;
        feedback_links_enabled = false;
      };
      news.news_feed_enabled = false;
      help.enabled = false;
      date_formats.use_browser_locale = true;
      # Prometheus metrics for the OTel agent (default.nix scrapes :3300).
      metrics.enabled = true;
    };
    declarativePlugins = [ pkgs.grafanaPlugins.grafana-clickhouse-datasource ];
    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name = "ClickHouse";
          type = "grafana-clickhouse-datasource";
          uid = "clickhouse";
          access = "proxy";
          isDefault = true;
          jsonData = {
            host = "127.0.0.1";
            port = 9000;
            protocol = "native";
            defaultDatabase = "otel";
            username = "default";
            dialTimeout = 10;
            queryTimeout = 60;
          };
        }
      ];
      dashboards.settings.providers = [
        {
          name = "railgun";
          type = "file";
          allowUiUpdates = false;
          options.path = "/etc/grafana/dashboards";
          options.foldersFromFilesStructure = true;
        }
      ];
    };
  };

  environment.etc = fleetEtc // nativelinkEtc;

  # The org is "straylight", not "Main Org." — there is no ini key for it, so
  # one idempotent PUT after Grafana is up.
  systemd.services.grafana-org-name = {
    description = "Name the Grafana org";
    after = [ "grafana.service" ];
    requires = [ "grafana.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.curl ];
    script = ''
      pw=$(cat ${adminPasswordFile})
      for i in $(seq 1 30); do
        curl -fsS -u "admin:$pw" http://127.0.0.1:3300/api/health >/dev/null && break
        sleep 2
      done
      curl -fsS -u "admin:$pw" -X PUT -H 'Content-Type: application/json' \
        -d '{"name":"straylight"}' http://127.0.0.1:3300/api/org >/dev/null
    '';
  };
}
