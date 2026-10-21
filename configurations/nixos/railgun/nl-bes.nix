# railgun — nl-bes: the Build Event Service for the straylight NativeLink console.
#
#   gRPC 0.0.0.0:50075   google.devtools.build.v1.PublishBuildEvent (Bazel --bes_backend)
#   HTTP 127.0.0.1:3311  /api/bes/* (served same-origin by nginx on nativelink.s4.gl)
#
# Ingests BEP into ClickHouse database `bes` (schema owned by the binary, created
# idempotently at start; SELECT granted to the console's read-only user), keeps the
# raw stream per invocation under /var/lib/nl-bes/raw, and enriches actions from
# Bazel's compact execution log (POST /api/bes/invocations/<id>/execlog) joined
# with NativeLink's ActionCache (ExecutedActionMetadata: worker, exact timestamps).
# Source: https://git.s4.gl/straylight/orbital-nativelink (backend/nl-bes).
{ pkgs, lib, ... }:
let
  # Pinned to a commit of the console repo on this host (branch lane/bes until the
  # coordinator merges; then ref = "main"). fetchGit with a rev is pure, so the
  # pure `nix build` deploy works; bump `rev` to ship a new nl-bes.
  repo = builtins.fetchGit {
    url = "file:///home/b7r6/src/hypermodern/orbital-nativelink";
    ref = "main";
    rev = "fb14598071707996b485a1ae25358a90c66a68e2";
  };
  src = repo + "/backend/nl-bes";
  nl-bes = pkgs.rustPlatform.buildRustPackage {
    pname = "nl-bes";
    version = "0.1.0";
    inherit src;
    cargoLock.lockFile = src + "/Cargo.lock";
    nativeBuildInputs = [ pkgs.protobuf pkgs.pkg-config ];
    PROTOC = "${pkgs.protobuf}/bin/protoc";
    doCheck = false;
    meta.description = "Build Event Service ingest + /api/bes for the straylight NativeLink console";
  };
in
{
  environment.systemPackages = [ nl-bes ];

  users.users.nl-bes = { isSystemUser = true; group = "nl-bes"; };
  users.groups.nl-bes = { };

  systemd.services.nl-bes = {
    description = "nl-bes — Build Event Service (BEP → ClickHouse) + /api/bes";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "clickhouse.service" "nativelink-scheduler.service" ];
    wants = [ "network-online.target" "clickhouse.service" ];
    environment = {
      NL_BES_CLICKHOUSE = "http://127.0.0.1:8123";
      NL_BES_STATE = "/var/lib/nl-bes";
      NL_BES_REAPI = "http://127.0.0.1:50051";
      NL_BES_INSTANCE = "main";
      NL_BES_GRPC = "0.0.0.0:50075";
      NL_BES_HTTP = "127.0.0.1:3311";
      RUST_LOG = "info";
    };
    serviceConfig = {
      ExecStart = "${nl-bes}/bin/nl-bes serve";
      User = "nl-bes";
      Group = "nl-bes";
      StateDirectory = "nl-bes";
      StateDirectoryMode = "0755";
      Restart = "on-failure";
      RestartSec = 3;
      # hardening
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      SystemCallArchitectures = "native";
      LimitNOFILE = 65536;
    };
  };

  # Bazel clients on the tailnet reach BES directly; nothing else gets to 50075.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 50075 ];

  # Same-origin JSON for the console. Exec-log uploads can be tens of MB.
  services.nginx.virtualHosts."nativelink.s4.gl".locations."/api/bes/" = {
    proxyPass = "http://127.0.0.1:3311";
    extraConfig = ''
      client_max_body_size 512m;
      proxy_read_timeout 300s;
      proxy_request_buffering off;
      add_header Cache-Control "no-store";
    '';
  };

  # Fixture drop for the other lanes (PROGRAM.md): world-readable BEP samples.
  systemd.tmpfiles.rules = [
    "d /var/lib/nl-bes 0755 nl-bes nl-bes -"
    "d /var/lib/nl-bes/raw 0755 nl-bes nl-bes -"
    "d /var/lib/nl-bes/fixtures 0777 root root -"
  ];
}
