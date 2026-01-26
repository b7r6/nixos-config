{
  description = "// hypermodern // nixos";

  outputs =
    inputs:
    inputs.nixos-unified.lib.mkFlake {
      inherit inputs;
      root = ./.;
    };

  inputs = {
    # aleph is the source of truth for core inputs
    aleph.url = "github:straylight-software/aleph?ref=b7r6/continuity-0x07";

    nixpkgs.follows = "aleph/nixpkgs";
    flake-parts.follows = "aleph/flake-parts";
    treefmt-nix.follows = "aleph/treefmt-nix";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    agenix-shell.url = "github:aciceri/agenix-shell";
    agenix-shell.inputs.nixpkgs.follows = "nixpkgs";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    hyprland.url = "github:hyprwm/Hyprland";
    # Don't follow nixpkgs - hyprland needs specific Qt6 versions
    # hyprland.inputs.nixpkgs.follows = "nixpkgs";

    hyprland-plugins.url = "github:hyprwm/hyprland-plugins";
    hyprland-plugins.inputs.hyprland.follows = "hyprland";

    hy3.url = "github:outfoxxed/hy3";
    hy3.inputs.hyprland.follows = "hyprland";

    nixos-unified.url = "github:srid/nixos-unified";
    nixid.url = "github:srid/nixid";

    home-manager.follows = "aleph/nix2gpu/home-manager";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    nvf.url = "github:NotAShelf/nvf";
    nvf.inputs.nixpkgs.follows = "nixpkgs";
    nvf.inputs.flake-parts.follows = "flake-parts";

    nix4nvchad.url = "github:nix-community/nix4nvchad";
    nix4nvchad.inputs.nixpkgs.follows = "nixpkgs";

    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";
    stylix.inputs.home-manager.follows = "home-manager";

    xremap-flake.url = "github:xremap/nix-flake?ref=master";
    xremap-flake.inputs.nixpkgs.follows = "nixpkgs";
    xremap-flake.inputs.home-manager.follows = "home-manager";
  };
}
