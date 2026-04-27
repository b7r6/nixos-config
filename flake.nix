{
  description = "// hypermodern // nixos";

  outputs =
    inputs:
    inputs.nixos-unified.lib.mkFlake {
      inherit inputs;
      root = ./.;
    };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    agenix-shell.url = "github:aciceri/agenix-shell";
    agenix-shell.inputs.nixpkgs.follows = "nixpkgs";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";

    impurity.url = "github:b7r6/impurity.nix";

    # Hyprland 0.53.0 with matching hy3 hl0.53.0.1
    # (hy3 hasn't caught up to 0.54.0 yet)
    hyprland.url = "github:hyprwm/Hyprland?ref=v0.53.0&submodules=1";

    hy3.url = "github:outfoxxed/hy3?ref=hl0.53.0.1";
    hy3.inputs.hyprland.follows = "hyprland";

    nixos-unified.url = "github:srid/nixos-unified";
    nixid.url = "github:srid/nixid";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    nvf.url = "github:NotAShelf/nvf";
    nvf.inputs.nixpkgs.follows = "nixpkgs";
    nvf.inputs.flake-parts.follows = "flake-parts";

    nix4nvchad.url = "github:nix-community/nix4nvchad";
    nix4nvchad.inputs.nixpkgs.follows = "nixpkgs";

    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    xremap-flake.url = "github:xremap/nix-flake?ref=master";
    xremap-flake.inputs.nixpkgs.follows = "nixpkgs";

    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    nix-compile.url = "git+ssh://git@github.com/straylight-software/nix-compile?ref=dev";
    nix-compile.inputs.nixpkgs.follows = "nixpkgs";
  };
}
