# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                               // hyper-modern-nixos // attic
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# attic.rs binary cache server (atticd), OFF BY DEFAULT.
#
# Uses the in-nixpkgs `pkgs.attic-server` + the upstream-maintained
# `services.atticd` NixOS module (already in our pinned nixpkgs) — NO new flake
# input required. Verified to build from the binary cache in this nixpkgs rev.
#
# Defaults: monolithic mode, sqlite at /var/lib/atticd/server.db, local storage
# at /var/lib/atticd/storage. Switch to postgres/S3 via `settings` if/when you
# outgrow that (postgres is already available via common/postgres.nix).
#
# Secret (REQUIRED when enabled): atticd needs an RS256 JWT signing secret,
# provided via an env file that defines:
#
#   ATTIC_SERVER_TOKEN_RS256_SECRET="$(openssl genrsa -traditional 4096)"
#
# Generate once, store it with agenix as `atticd-rs256.<host>.age`, and wire
# `age.secrets.atticd-rs256` to decrypt it. This module points
# `services.atticd.environmentFile` at that decrypted path. Inert until enabled.

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.attic;
in
{
  options.hyper-modern-nixos.attic = {
    enable = lib.mkEnableOption "atticd nix binary cache server (off by default)";

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/agenix/atticd-rs256";
      description = ''
        Path to the env file defining ATTIC_SERVER_TOKEN_RS256_SECRET. A host
        that enables attic should declare `age.secrets.atticd-rs256`
        (file = atticd-rs256.age), import the agenix nixos module, and set this
        to that decrypted runtime path. Must NOT be a store path.
      '';
    };

    listen = lib.mkOption {
      type = lib.types.str;
      default = "[::1]:8080";
      example = "[::]:8080";
      description = ''
        Address atticd listens on. Defaults to loopback only — expose it on the
        tailnet (or behind a reverse proxy) deliberately rather than by accident.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the atticd listen port in the firewall (only meaningful if the firewall is enabled).";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Extra settings merged into services.atticd.settings (TOML). e.g. database.url, storage.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.environmentFile != null;
        message = ''
          hyper-modern-nixos.attic.enable is true but no environmentFile is set
          and no agenix secret `atticd-rs256` is defined. atticd needs an RS256
          JWT secret. Generate one:
            openssl genrsa -traditional 4096 | { echo -n 'ATTIC_SERVER_TOKEN_RS256_SECRET='; cat; }
          store it via agenix as atticd-rs256.<host>.age, and wire age.secrets.
        '';
      }
    ];

    services.atticd = {
      enable = true;
      inherit (cfg) environmentFile;
      settings = lib.recursiveUpdate { inherit (cfg) listen; } cfg.settings;
    };

    # Client CLI for `attic login` / `attic push` / `attic use`.
    environment.systemPackages = [ pkgs.attic-client ];

    networking.firewall = lib.mkIf cfg.openFirewall (
      let
        port = lib.toInt (lib.last (lib.splitString ":" cfg.listen));
      in
      {
        allowedTCPPorts = [ port ];
      }
    );
  };
}
