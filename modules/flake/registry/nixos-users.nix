# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                       // hypermodern // registry // users → NixOS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# consumes the rendered user registry JSON and drives:
#   - hyper-modern-nixos.users (SSH keys, groups)
#   - services.kanidm.provision (persons, groups, OIDC scope maps)
#   - grafana OIDC client (when wired)
#
# this module is imported by the flake module system, NOT per-host.
# it provides fleet-wide user configuration from a single source.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  registryDir = ./data;

  # render users.dhall → JSON at build time
  usersJson =
    pkgs.runCommand "users-registry.json"
      {
        nativeBuildInputs = [ pkgs.dhall-json ];
      }
      ''
        dhall-to-json --file ${registryDir}/render-users.dhall > $out
      '';

  users = builtins.fromJSON (builtins.readFile usersJson);

  # helper: does a user belong to a group?
  hasGroup = user: group: builtins.elem group user.groups;

  # all unique groups referenced by any user
  allGroups = lib.unique (lib.concatMap (u: u.groups) users);

  # users in a specific group
  usersInGroup = group: builtins.filter (u: hasGroup u group) users;

  # admin users (fleet_admins)
  admins = usersInGroup "fleet_admins";

  cfg = config.hyper-modern-nixos.identity;
in
{
  options.hyper-modern-nixos.identity = {
    enable = (lib.mkEnableOption "fleet identity from the user registry") // {
      default = true;
    };

    kanidm = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to provision Kanidm from the user registry (only on the IdP host).";
    };
  };

  config = lib.mkIf cfg.enable {

    # ── NixOS user accounts (ensures they exist even without home-manager) ────
    users.users = lib.listToAttrs (
      map (user: {
        name = user.name;
        value = {
          isNormalUser = true;
          extraGroups = lib.optional (hasGroup user "fleet_admins") "wheel" ++ [ "networkmanager" ];
          openssh.authorizedKeys.keys = user.sshKeys;
        };
      }) users
    );

    # ── SSH authorized keys (merged with myusers for users that have home configs)
    hyper-modern-nixos.users.users = lib.listToAttrs (
      map (user: {
        name = user.name;
        value = {
          isAdmin = hasGroup user "fleet_admins";
          authorizedKeys = user.sshKeys;
        };
      }) users
    );

    # ── Kanidm provisioning (only where kanidm = true) ───────────────────────
    services.kanidm.provision = lib.mkIf cfg.kanidm {

      # groups: one per registry Group, members derived from user.groups
      groups = lib.listToAttrs (
        map (group: {
          name = group;
          value = {
            members = map (u: u.name) (usersInGroup group);
          };
        }) allGroups
      );

      # persons: one per user
      persons = lib.listToAttrs (
        map (user: {
          name = user.name;
          value = {
            displayName = user.displayName;
            mailAddresses = [ user.email ];
            groups = user.groups;
          };
        }) users
      );

      # OIDC clients get scope maps from forgejo_users group
      systems.oauth2.forgejo = {
        scopeMaps.forgejo_users = [
          "openid"
          "email"
          "profile"
        ];
      };
    };

    # ── Grafana OIDC (future: wire when kanidm client is provisioned) ─────────
    # services.grafana.settings."auth.generic_oauth" = { ... };
  };
}
