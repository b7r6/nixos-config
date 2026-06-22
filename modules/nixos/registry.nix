# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                             // hyper-modern-nixos // registry
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# zot — OCI image registry, OFF BY DEFAULT. A plain systemd service (no Docker
# daemon), blobs stored in Cloudflare R2 via zot's core S3 driver.
#
# State tiering (see docs/architecture/state-and-backup.md): the registry's
# authoritative content (blobs + manifests) lives in R2, so the local
# /var/lib/zot dir is purely a `reconstructible` cache — persisted across an
# impermanence reboot (warm), never restic'd. There is no separate DB: with
# remote storage we run dedupe=false (the dedupe index would need a remote DB),
# so nothing here needs PITR/dumps.
#
# Credentials: the R2 access key / secret come from an agenix env file as the
# AWS SDK vars (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY), fed to the service via
# systemd EnvironmentFile — never the nix store. Self-wired like the other R2
# consumers.
{
  config,
  lib,
  pkgs,
  flake ? null,
  ...
}:
let
  cfg = config.hyper-modern-nixos.registry;
  machineSecrets = flake.self + "/secrets/agenix/machines";

  # zot config (non-secret). Creds arrive via AWS_* env from the agenix file.
  zotConfig = {
    distSpecVersion = "1.1.1";
    storage = {
      rootDirectory = cfg.dataDir;
      # Remote storage without a remote dedupe-index DB ⇒ dedupe must be off.
      dedupe = false;
      gc = true;
      storageDriver = {
        name = "s3";
        rootdirectory = "/";
        region = cfg.s3.region;
        bucket = cfg.s3.bucket;
        regionendpoint = cfg.s3.endpoint;
        secure = true;
        forcepathstyle = true;
      };
    };
    http = {
      address = cfg.listenAddress;
      port = toString cfg.port;
    };
    log.level = cfg.logLevel;
  };

  configFile = (pkgs.formats.json { }).generate "zot-config.json" zotConfig;
in
{
  options.hyper-modern-nixos.registry = {
    enable = lib.mkEnableOption "zot OCI registry (R2-backed, off by default)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.zot;
      defaultText = "pkgs.zot";
      description = "The zot package to run.";
    };

    listenAddress = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = ''
        Bind address. Bound broad so it's reachable on the tailnet (binding the
        tailscale0 IP directly races boot); the firewall (on fleet-wide) opens
        `port` ONLY on tailscale0, so it is not publicly exposed. Front with
        `tailscale serve` to reach it off-tailnet.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 5000;
      description = "Registry HTTP port (opened on tailscale0 only).";
    };

    openTailnet = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the registry port on tailscale0 only.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/zot";
      description = ''
        Local working dir (cache/scratch). Classified `reconstructible` state —
        the authoritative blobs live in R2 — so it's persisted across an
        impermanence reboot but never backed up.
      '';
    };

    logLevel = lib.mkOption {
      type = lib.types.enum [
        "debug"
        "info"
        "warn"
        "error"
      ];
      default = "info";
      description = "zot log level.";
    };

    secret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "zot-r2-env";
      description = ''
        agenix machine-secret NAME (decrypts to /run/agenix/<name>) providing the
        R2 creds as AWS SDK env vars:
          AWS_ACCESS_KEY_ID=...
          AWS_SECRET_ACCESS_KEY=...
        The module self-wires age.secrets.<name> from the repo. null = wire the
        EnvironmentFile yourself.
      '';
    };

    s3 = {
      bucket = lib.mkOption {
        type = lib.types.str;
        default = "straylight-oci";
        description = "R2 bucket for the OCI blob store.";
      };
      endpoint = lib.mkOption {
        type = lib.types.str;
        default = "6063b6652178f5cf1cfb87e7e41acf1e.r2.cloudflarestorage.com";
        description = "R2 S3 endpoint host (account-scoped). Non-secret.";
      };
      region = lib.mkOption {
        type = lib.types.str;
        default = "auto";
        description = "S3 region (R2 = auto).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.secret != null;
        message = ''
          hyper-modern-nixos.registry.enable is true but .secret is null. zot needs
          the R2 creds (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY) from an agenix env
          file — never the store. Set .secret (default zot-r2-env) or wire the
          EnvironmentFile yourself.
        '';
      }
    ];

    # Self-wire the R2 creds secret (root-owned; only root runs the unit's pre).
    age.secrets = lib.mkIf (cfg.secret != null) {
      ${cfg.secret}.file = machineSecrets + "/${cfg.secret}.age";
    };

    # Local working dir = reconstructible cache (persist on impermanence, never
    # restic'd — R2 holds the authoritative blobs).
    hyper-modern-nixos.state.dirs.zot = {
      path = cfg.dataDir;
      class = "reconstructible";
    };

    environment.systemPackages = [ cfg.package ];

    systemd.services.zot = {
      description = "zot OCI registry (R2-backed)";
      after = [
        "network-online.target"
        "agenix.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      # Re-exec on cred change so it always has live R2 keys.
      restartTriggers = [ configFile ] ++ lib.optional (cfg.secret != null) "/run/agenix/${cfg.secret}";
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} serve ${configFile}";
        # R2 creds (AWS_*) from the agenix env file — never the store.
        EnvironmentFile = lib.mkIf (cfg.secret != null) "/run/agenix/${cfg.secret}";
        Restart = "on-failure";
        RestartSec = 5;
        # zot manages its own state dir; systemd creates + owns it.
        StateDirectory = "zot";
        DynamicUser = true;
        # Hardening — zot is a network-facing service.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
    };

    # Tailnet-only exposure (enforced — firewall is on fleet-wide).
    networking.firewall.interfaces = lib.mkIf cfg.openTailnet {
      tailscale0.allowedTCPPorts = [ cfg.port ];
    };
  };
}
