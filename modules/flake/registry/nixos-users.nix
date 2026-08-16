# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                       // hypermodern // registry // users → NixOS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The ONE user module. Consumes the typed user registry (data/users.dhall,
# rendered to JSON via IFD) and is the single source for everything a user is:
#
#   - NixOS accounts        (users.users.<name>: normal user, groups, ssh keys)
#   - home-manager configs  (home-manager.users.<name>, auto-imported when a
#                            configurations/home/<name>.nix exists — SSH/OIDC-only
#                            users simply omit the file)
#   - nix trusted-users
#   - Kanidm provisioning   (persons, groups, OIDC scope maps — IdP host only)
#
# This supersedes the old modules/nixos/myusers.nix: there is no longer a second
# auto-discovery path or a hyper-modern-nixos.users option tree. Add a user by
# adding ONE entry to data/users.dhall (+ an optional home config); everything
# below derives from it.
#
# ── group model ──────────────────────────────────────────────────────────────
# Every managed user gets `defaultGroups` (baseline, e.g. networkmanager).
# fleet_admins additionally get `adminGroups` (wheel + the privileged system
# groups: docker/libvirtd/…). A user's ssh keys are ONLY their own — admins act
# as another user via `sudo`, not by cross-installed keys.
#
# ── host scoping ───────────────────────────────────────────────────────────────
# user.hosts = [] means "every managed host"; a non-empty list restricts the
# ACCOUNT (and home config) to those hosts. Kanidm persons/groups are always
# provisioned for every registry user regardless of host.
#
# this module is imported fleet-wide (modules/nixos/default.nix), NOT per-host.
{
  lib,
  config,
  pkgs,
  flake,
  ...
}:
let
  inherit (flake) self;

  registryDir = ./data;

  # render users.dhall → JSON at eval time (IFD), same pattern as the topology
  # registry (nixos.nix): buildPackages so cross-arch hosts don't demand a native
  # dhall build, + the locale fix for the unicode in the Dhall comments.
  buildPkgs = pkgs.buildPackages;

  usersJson =
    buildPkgs.runCommand "users-registry.json"
      {
        nativeBuildInputs = [ buildPkgs.dhall-json ];
        LANG = "C.UTF-8";
        LC_ALL = "C.UTF-8";
        LOCALE_ARCHIVE = "${buildPkgs.glibcLocales}/lib/locale/locale-archive";
      }
      ''
        export HOME="$TMPDIR"
        export XDG_CACHE_HOME="$TMPDIR/dhall-cache"
        mkdir -p "$XDG_CACHE_HOME"
        dhall-to-json --file ${registryDir}/render-users.dhall > $out
      '';

  users = builtins.fromJSON (builtins.readFile usersJson);

  # ── registry helpers ─────────────────────────────────────────────────────────
  hasGroup = user: group: builtins.elem group user.groups;
  isAdmin = user: hasGroup user "fleet_admins";

  allGroups = lib.unique (lib.concatMap (u: u.groups) users);
  usersInGroup = group: builtins.filter (u: hasGroup u group) users;

  # users whose ACCOUNT belongs on THIS host (empty hosts = everywhere)
  hostName = config.networking.hostName;
  onThisHost = user: user.hosts == [ ] || builtins.elem hostName user.hosts;
  hostUsers = builtins.filter onThisHost users;

  # does this user have a home-manager config to import?
  homeFile = name: self + "/configurations/home/${name}.nix";
  hasHome = name: builtins.pathExists (homeFile name);

  cfg = config.hyper-modern-nixos.identity;

  resolvedGroups = user: cfg.defaultGroups ++ lib.optionals (isAdmin user) cfg.adminGroups;
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

    defaultGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "networkmanager" ];
      description = "System groups every managed user is added to on every host.";
    };

    adminGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "wheel"
        "docker"
        "adbusers"
        "libvirtd"
        "wireshark"
      ];
      description = ''
        Additional (privileged) system groups granted ONLY to fleet_admins users
        on top of defaultGroups. Kept off non-admins because e.g. docker is
        root-equivalent.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # ── NixOS accounts (host-scoped) ──────────────────────────────────────────
    users.users = lib.listToAttrs (
      map (user: {
        inherit (user) name;
        value =
          lib.optionalAttrs pkgs.stdenv.isDarwin { home = "/Users/${user.name}"; }
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            isNormalUser = true;
            extraGroups = resolvedGroups user;
            openssh.authorizedKeys.keys = user.sshKeys;
          };
      }) hostUsers
    );

    # ── home-manager (auto-imported when a home config exists) ────────────────
    # Per-host home tweaks (monitor layout, etc.) still merge cleanly on top via
    # a plain `home-manager.users.<name> = { … }` in the host's configuration.nix.
    home-manager.users = lib.listToAttrs (
      map (user: {
        inherit (user) name;
        value.imports = [ (homeFile user.name) ];
      }) (builtins.filter (u: hasHome u.name) hostUsers)
    );

    # ── nix trusted-users ─────────────────────────────────────────────────────
    nix.settings.trusted-users = [ "root" ] ++ map (u: u.name) hostUsers;

    # ── Kanidm provisioning (IdP host only; ALL users, host-independent) ──────
    services.kanidm.provision = lib.mkIf cfg.kanidm {

      # groups: one per registry Group, members derived from user.groups
      groups = lib.listToAttrs (
        map (group: {
          name = group;
          value.members = map (u: u.name) (usersInGroup group);
        }) allGroups
      );

      # persons: one per user
      persons = lib.listToAttrs (
        map (user: {
          inherit (user) name;
          value = {
            inherit (user) displayName;
            mailAddresses = [ user.email ];
            inherit (user) groups;
          };
        }) users
      );

      # OIDC clients get scope maps from the forgejo_users group
      systems.oauth2.forgejo = {
        scopeMaps.forgejo_users = [
          "openid"
          "email"
          "profile"
        ];
      };
    };
  };
}
