# railgun — nl-inspect: ORBITAL // NATIVELINK's stateless REAPI/CAS inspector
# behind https://nativelink.s4.gl/api/re/ (contract: orbital-nativelink/docs/PROGRAM.md).
#
# A Rust service (tonic client + axum) that turns the live NativeLink into JSON:
# Capabilities, ByteStream reads with typed proto decoding, FindMissingBlobs,
# GetTree walks, Action → Command → ActionResult, WaitExecution on a named
# operation, and the scheduler's per-worker gauges (via ClickHouse's read-only
# `console` user). Loopback only; nginx fronts it on the console's vhost.
#
# Source is the console repo on the Forge, pinned by rev (bump `rev` + `hash`
# on each release; `nix flake prefetch` the URL or let the mismatch tell you).
{ pkgs, lib, ... }:
let
  src = builtins.fetchGit {
    url = "https://git.s4.gl/straylight/orbital-nativelink.git";
    ref = "main";
    rev = "fb14598071707996b485a1ae25358a90c66a68e2";
  };

  nl-inspect = pkgs.rustPlatform.buildRustPackage {
    pname = "nl-inspect";
    version = "0.1.0";
    src = "${src}/backend/nl-inspect";
    cargoLock.lockFile = "${src}/backend/nl-inspect/Cargo.lock";
    doCheck = false;
    meta = {
      description = "ORBITAL // NATIVELINK — stateless REAPI/CAS inspector (/api/re)";
      mainProgram = "nl-inspect";
    };
  };
in
{
  environment.systemPackages = [ nl-inspect ];

  systemd.services.nl-inspect = {
    description = "nl-inspect — REAPI/CAS inspector for the NativeLink console (/api/re)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
      "nativelink-scheduler.service"
    ];
    environment = {
      NL_INSPECT_LISTEN = "127.0.0.1:3310";
      NL_INSPECT_REAPI = "http://127.0.0.1:50051";
      NL_INSPECT_CLICKHOUSE = "http://console@127.0.0.1:8123/";
      RUST_LOG = "nl_inspect=info";
    };
    serviceConfig = {
      ExecStart = lib.getExe nl-inspect;
      Restart = "always";
      RestartSec = 2;
      DynamicUser = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
      CapabilityBoundingSet = "";
      IPAddressAllow = [ "localhost" ];
      IPAddressDeny = "any";
    };
  };

  # Same-origin on the console's vhost: /api/re/ → nl-inspect.
  services.nginx.virtualHosts."nativelink.s4.gl".locations."/api/re/" = {
    proxyPass = "http://127.0.0.1:3310";
    extraConfig = ''
      proxy_read_timeout 180s;
      proxy_buffering off;
      client_max_body_size 8m;
    '';
  };
}
