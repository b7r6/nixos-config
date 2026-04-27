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

}
