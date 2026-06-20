# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                       // hyper-modern-nixos // attic-replica
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# "Be a fleet attic api-server replica." A one-flag role that captures the
# repeated wiring so each consuming host is just:
#
#     age.secrets.atticd-rs256.file      = …/atticd-rs256.age;
#     age.secrets.attic-push-token.file  = …/attic-push-token.age;
#     hyper-modern-nixos.attic-replica.enable = true;
#
# It configures the underlying hyper-modern-nixos.attic module as a STATELESS
# api-server sharing the fleet's postgres (on watchtower) + R2 chunk store +
# RS256 signing secret, and points this host's nix substituters at its OWN
# localhost:8080 (first in line) with watch-store auto-push. watchtower itself
# does NOT use this role — it runs mode="monolithic" (api-server + the single
# garbage collector) directly. See modules/nixos/attic.nix for the topology.
{ config, lib, ... }:
let
  cfg = config.hyper-modern-nixos.attic-replica;
in
{
  options.hyper-modern-nixos.attic-replica = {
    enable = lib.mkEnableOption "attic api-server replica (shared pg + R2, local substituter)";

    environmentFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/atticd-rs256";
      description = ''
        Decrypted env file carrying ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64
        (identical fleet-wide), PGPASSWORD (the atticd postgres role password,
        read by sqlx), and AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY (R2). The host
        must declare age.secrets.atticd-rs256 pointing at the agenix file.
      '';
    };

    databaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "postgresql://atticd@watchtower.osiris-walleye.ts.net/atticd";
      description = "Passwordless shared-postgres connection string (PGPASSWORD via pgPasswordFile).";
    };

    pgPasswordFile = lib.mkOption {
      type = lib.types.path;
      default = "/run/agenix/atticd-pgpassword";
      description = "Decrypted env file with PGPASSWORD for the shared postgres (agenix).";
    };

    pushTokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/agenix/attic-push-token";
      description = "Decrypted push JWT for watch-store auto-push (agenix).";
    };

    bucket = lib.mkOption {
      type = lib.types.str;
      default = "straylight-attic-cache";
      description = "Shared R2 chunk-store bucket (owned fleet-wide by atticd).";
    };

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "https://6063b6652178f5cf1cfb87e7e41acf1e.r2.cloudflarestorage.com";
      description = "R2 S3 endpoint.";
    };

    publicKey = lib.mkOption {
      type = lib.types.str;
      default = "hypermodern:IxmiCAZWTeYmnOafmhz39qrn0wXj+aNvBy9dczJTcAs=";
      description = "The `hypermodern` cache's binary-cache public key.";
    };
  };

  config = lib.mkIf cfg.enable {
    hyper-modern-nixos.attic = {
      enable = true;
      mode = "api-server";
      inherit (cfg) environmentFile databaseUrl pgPasswordFile;
      listen = "[::]:8080";
      trustedInterfaces = [ "tailscale0" ];

      storage = {
        type = "s3";
        region = "auto";
        inherit (cfg) bucket endpoint;
      };

      # Consult our OWN local api-server first; push every build into the shared
      # cache. localhost means no serialization through any single box.
      clientCache = {
        enable = true;
        name = "hypermodern";
        endpoint = "http://localhost:8080";
        inherit (cfg) publicKey pushTokenFile;
      };
    };
  };
}
