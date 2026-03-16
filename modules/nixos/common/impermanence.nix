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
      default = [
        "/etc/machine-id"
      ];
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
    # Ensure persist directory exists on the persistent subvolume
    fileSystems.${cfg.persistPath} = lib.mkDefault {
      device = "/dev/disk/by-label/nixos";
      fsType = "btrfs";
      options = [
        "subvol=@persist"
        "compress=zstd:1"
        "noatime"
      ];
      neededForBoot = true;
    };

    environment.persistence.${cfg.persistPath} = {
      hideMounts = true;
      directories = cfg.directories;
      files = cfg.files;
      users = lib.mapAttrs (_: userCfg: {
        directories = userCfg.directories;
        files = userCfg.files;
      }) cfg.users;
    };

    # Essential for impermanence - blank the root on boot
    # This assumes btrfs with a @ subvolume for root
    boot.initrd.postDeviceCommands = lib.mkAfter ''
      mkdir -p /mnt
      mount -o subvol=/ /dev/disk/by-label/nixos /mnt

      # Delete old root and recreate
      if [[ -e /mnt/@root-blank ]]; then
        btrfs subvolume delete /mnt/@
        btrfs subvolume snapshot /mnt/@root-blank /mnt/@
      fi

      umount /mnt
    '';

    # Warn about things that won't persist
    warnings =
      if cfg.enable && cfg.users == { } then
        [ "impermanence enabled but no users configured - user data will not persist!" ]
      else
        [ ];
  };
}
