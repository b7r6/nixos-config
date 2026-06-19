# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // myusers
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Declarative fleet user model.
#
# Usernames are still auto-discovered from configurations/home/*.nix (one home
# config per user). What used to be hand-pasted per host — SSH authorized keys
# and group membership — is now configured ONCE here, globally and per-user:
#
#   hyper-modern-nixos.users = {
#     # applied to every managed user on every host
#     defaultGroups     = [ "wheel" "networkmanager" "docker" ... ];
#     defaultAuthorizedKeys = [ "ssh-ed25519 ..." ];
#
#     # per-user, MERGED on top of the global defaults
#     users.b7r6 = {
#       extraGroups    = [ "wireshark" ];          # added to defaultGroups
#       authorizedKeys = [ "ssh-ed25519 ...other" ]; # added to defaultAuthorizedKeys
#       isAdmin        = true;                      # convenience: ensures wheel
#     };
#   };
#
# A host that needs an extra group for a user just adds to extraGroups in its
# own configuration.nix (option merge), instead of redeclaring users.users.
{
  flake,
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (flake.inputs) self;

  cfg = config.hyper-modern-nixos.users;

  # Auto-discovered usernames: every regular file configurations/home/<name>.nix.
  discoveredUsers =
    let
      dirContents = builtins.readDir (self + /configurations/home);
      regularFiles = lib.filterAttrs (_: t: t == "regular") dirContents;
    in
    map (n: lib.removeSuffix ".nix" n) (builtins.attrNames regularFiles);

  userNames = if cfg.names != null then cfg.names else discoveredUsers;

  # Per-user resolved attrs (defaults ⊕ per-user overlay).
  perUser = name: cfg.users.${name} or { };

  resolvedGroups =
    name:
    lib.unique (
      cfg.defaultGroups
      ++ (perUser name).extraGroups or [ ]
      ++ lib.optional ((perUser name).isAdmin or true) "wheel"
    );

  resolvedKeys = name: lib.unique (cfg.defaultAuthorizedKeys ++ (perUser name).authorizedKeys or [ ]);
in
{
  options.hyper-modern-nixos.users = {
    names = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      defaultText = lib.literalExpression "all users under ./configurations/home";
      description = "Managed usernames. null = auto-discover from configurations/home/*.nix.";
    };

    defaultGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "networkmanager"
        "wheel"
        "docker"
        "adbusers"
        "libvirtd"
        "wireshark"
      ];
      description = "Groups every managed user is added to on every host.";
    };

    defaultAuthorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH authorized keys granted to every managed user on every host.";
    };

    users = lib.mkOption {
      default = { };
      description = "Per-user overrides, merged on top of the global defaults.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            isAdmin = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether the user is in the wheel group (passwordless sudo is set elsewhere).";
            };

            extraGroups = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Groups added to this user IN ADDITION TO defaultGroups.";
            };

            authorizedKeys = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "SSH keys added to this user IN ADDITION TO defaultAuthorizedKeys.";
            };
          };
        }
      );
    };
  };

  config = {
    users.users = lib.genAttrs userNames (
      name:
      lib.optionalAttrs pkgs.stdenv.isDarwin { home = "/Users/${name}"; }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        isNormalUser = true;
        extraGroups = resolvedGroups name;
        openssh.authorizedKeys.keys = resolvedKeys name;
      }
    );

    home-manager.users = lib.genAttrs userNames (name: {
      imports = [ (self + /configurations/home/${name}.nix) ];
    });

    nix.settings.trusted-users = [ "root" ] ++ userNames;
  };
}
