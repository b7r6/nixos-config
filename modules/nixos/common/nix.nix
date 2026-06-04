# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                           // hyper-modern-nixos // nix daemon
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Nix daemon configuration: flakes, experimental features, garbage collection.
#
{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
in
{
  nix = {
    package = pkgs.nixVersions.stable;

    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

    extraOptions = ''
      experimental-features = nix-command flakes pipe-operators
    '';

    settings = {
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "@wheel"
      ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [
    # Fix nvidia driver disallowedReferences issue on aarch64
    (_final: prev: {
      # The nvidia-x11 package has disallowedReferences = [ kernel.dev ] which breaks on aarch64
      linuxPackages = prev.linuxPackages.extend (lpfinal: lpprev: {
        nvidia_x11 = lpprev.nvidia_x11.overrideAttrs (old: {
          disallowedReferences = [];
          # Also override the kernel modules
          passthru = old.passthru // {
            kernelModule = old.passthru.kernelModule.overrideAttrs (moduleOld: {
              disallowedReferences = [];
            });
          };
        });
      });

      linuxPackages_latest = prev.linuxPackages_latest.extend (lpfinal: lpprev: {
        nvidia_x11 = lpprev.nvidia_x11.overrideAttrs (old: {
          disallowedReferences = [];
          # Also override the kernel modules
          passthru = old.passthru // {
            kernelModule = old.passthru.kernelModule.overrideAttrs (moduleOld: {
              disallowedReferences = [];
            });
          };
        });
      });
    })
  ];
}
