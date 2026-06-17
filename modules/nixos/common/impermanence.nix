{
  config,
  lib,
  flake,
  ...
}:
let
  cfg = config.hyper-modern-nixos.impermanence;
  inherit (flake) inputs;
in
{
  imports = [ inputs.impermanence.nixosModules.impermanence ];

  options.hyper-modern-nixos.impermanence = {
    enable = lib.mkEnableOption "impermanence - ephemeral root with persistent state";

    persistPath = lib.mkOption {
      type = lib.types.str;
      default = "/persist";
      description = "Path to the persistent storage";
    };

    # ── Disk layout (do NOT hardcode; a wrong value here is destructive) ──────
    # These describe the btrfs layout used for both the /persist mount and the
    # optional root rollback. They MUST match the host's actual disko/fileSystems
    # layout. There is intentionally no safe universal default for the device.
    device = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/disk/by-label/nixos";
      description = "btrfs block device hosting the @persist (and optionally @) subvolumes. Must match this host's disk.";
    };

    persistSubvol = lib.mkOption {
      type = lib.types.str;
      default = "@persist";
      description = "btrfs subvolume mounted at persistPath.";
    };

    manageFilesystem = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether this module should declare fileSystems.<persistPath>. Off by
        default: most hosts declare their own fileSystems via disko/
        hardware-configuration. Only turn on for a host whose layout exactly
        matches `device`/`persistSubvol`.
      '';
    };

    rollbackRoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        DESTRUCTIVE. Roll the root subvolume back to a blank snapshot on every
        boot (true ephemeral root). Requires a btrfs layout with `@` (root) and
        `@root-blank` (pristine snapshot) on `device`. Off by default because a
        mismatched layout here DELETES THE LIVE ROOT. Only enable on a host you
        built specifically for this (disko), never retrofit onto an existing box.
      '';
    };

    rollbackUseSystemdInitrd = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use a systemd-initrd service for the rollback instead of
        boot.initrd.postDeviceCommands. postDeviceCommands silently does NOTHING
        when boot.initrd.systemd.enable is true, so this must be true on hosts
        using systemd in initrd or the rollback will not happen (state drifts).
      '';
    };

    # Directories that should persist across reboots
    directories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/var/log"
        "/var/lib/bluetooth"
        "/var/lib/nixos"
        "/var/lib/systemd/coredump"
        "/var/lib/tailscale"
        "/var/lib/docker"
        "/var/lib/libvirt"
        "/var/lib/postgresql"
        "/var/lib/redis"
        "/etc/NetworkManager/system-connections"
        "/etc/ssh"
      ];
      description = "System directories to persist";
    };

    files = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/etc/machine-id" ];
      description = "System files to persist";
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            directories = lib.mkOption {
              type = lib.types.listOf (
                lib.types.either lib.types.str (
                  lib.types.submodule {
                    options = {
                      directory = lib.mkOption {
                        type = lib.types.str;
                        description = "Directory path";
                      };
                      mode = lib.mkOption {
                        type = lib.types.str;
                        default = "0755";
                        description = "Directory permissions";
                      };
                    };
                  }
                )
              );
              default = [
                "Documents"
                "Downloads"
                "Music"
                "Pictures"
                "Videos"
                "src"
                ".gnupg"
                ".ssh"
                ".local/share/atuin"
                ".local/share/direnv"
                ".local/state/nvim"
                ".local/state/wireplumber"
                ".config/gh"
                ".config/discord"
                ".config/spotify"
                ".mozilla"
                ".cache/nix"
              ];
              description = "User directories to persist";
            };

            files = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [
                ".bash_history"
                ".zsh_history"
              ];
              description = "User files to persist";
            };
          };
        }
      );
      default = { };
      description = "Per-user persistence configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.manageFilesystem || cfg.device != null;
        message = "impermanence.manageFilesystem is true but .device is null. Set the btrfs device that hosts ${cfg.persistSubvol}.";
      }
      {
        # The destructive rollback is the loaded gun. Refuse to wire it unless
        # the operator has explicitly named the device, so it can never run
        # against a label that happens to exist on an unrelated disk.
        assertion = !cfg.rollbackRoot || cfg.device != null;
        message = "impermanence.rollbackRoot is true but .device is null. This is DESTRUCTIVE; you must set .device to the btrfs device with @ and @root-blank subvolumes.";
      }
    ];

    # Only declare the persist mount when explicitly asked. Most hosts manage
    # their own fileSystems (disko / hardware-configuration), and silently
    # injecting a btrfs mount with a guessed device is how data gets lost.
    fileSystems = lib.mkIf cfg.manageFilesystem {
      ${cfg.persistPath} = {
        inherit (cfg) device;
        fsType = "btrfs";
        options = [
          "subvol=${cfg.persistSubvol}"
          "compress=zstd:1"
          "noatime"
        ];
        neededForBoot = true;
      };
    };

    environment.persistence.${cfg.persistPath} = {
      hideMounts = true;
      inherit (cfg) directories;
      inherit (cfg) files;
      users = lib.mapAttrs (_: userCfg: {
        inherit (userCfg) directories;
        inherit (userCfg) files;
      }) cfg.users;
    };

    # Blank the root on boot — ONLY when rollbackRoot is explicitly enabled AND a
    # device is named (enforced by the assertion above). Legacy initrd path.
    boot.initrd.postDeviceCommands =
      lib.mkIf (cfg.rollbackRoot && cfg.device != null && !cfg.rollbackUseSystemdInitrd)
        (
          lib.mkAfter ''
            mkdir -p /mnt
            mount -o subvol=/ ${toString cfg.device} /mnt
            if [[ -e /mnt/@root-blank ]]; then
              btrfs subvolume delete /mnt/@
              btrfs subvolume snapshot /mnt/@root-blank /mnt/@
            fi
            umount /mnt
          ''
        );

    # systemd-initrd path: postDeviceCommands is a no-op under systemd initrd, so
    # hosts using it MUST take this branch or the rollback silently never runs.
    boot.initrd.systemd.services.rollback-root =
      lib.mkIf (cfg.rollbackRoot && cfg.device != null && cfg.rollbackUseSystemdInitrd)
        {
          description = "Rollback btrfs root to a pristine snapshot";
          wantedBy = [ "initrd.target" ];
          after = [ "initrd-root-device.target" ];
          before = [ "sysroot.mount" ];
          unitConfig.DefaultDependencies = "no";
          serviceConfig.Type = "oneshot";
          script = ''
            mkdir -p /mnt
            mount -o subvol=/ ${toString cfg.device} /mnt
            if [[ -e /mnt/@root-blank ]]; then
              btrfs subvolume delete /mnt/@
              btrfs subvolume snapshot /mnt/@root-blank /mnt/@
            fi
            umount /mnt
          '';
        };

    # Warn about things that won't persist
    warnings =
      lib.optional (
        cfg.users == { }
      ) "impermanence enabled but no users configured - user data will not persist!"
      ++
        lib.optional (cfg.rollbackRoot && !cfg.rollbackUseSystemdInitrd)
          "impermanence.rollbackRoot uses boot.initrd.postDeviceCommands, which is a NO-OP under systemd initrd. If this host uses boot.initrd.systemd.enable, set rollbackUseSystemdInitrd=true or the root will NOT be wiped (state will drift).";
  };
}
