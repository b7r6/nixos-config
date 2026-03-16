{
  flake,
  pkgs,
  lib,
  ...
}:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    # Only import the wayland module we're testing - skip default/common entirely
    self.nixosModules.wayland
    ./configuration.nix
  ];

  # Use aarch64-linux for Apple Silicon Macs (where you're developing)
  # Change to x86_64-linux for Intel/AMD machines
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # Essential settings (minimal subset needed for VM)
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
  nixpkgs.config.allowUnfree = true;
  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "hm-backup";

  nix = {
    package = pkgs.nixVersions.stable;
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
  };

  security.sudo.wheelNeedsPassword = false;
}
