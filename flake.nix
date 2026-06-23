{
  description = "// hypermodern // nixos";

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [
        ./modules/flake/toplevel.nix
        ./configurations
      ];
    };

  inputs = {
    # nixpkgs: the sensenet-ai fork at HEAD (NOT upstream nixpkgs-unstable). The
    # whole tree rides this via `follows = "nixpkgs"`; pin anything we touch to it.
    nixpkgs.url = "github:sensenet-ai/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default-linux";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    agenix-shell.url = "github:aciceri/agenix-shell";
    agenix-shell.inputs.nixpkgs.follows = "nixpkgs";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    impermanence.url = "github:nix-community/impermanence";

    impurity.url = "github:outfoxxed/impurity.nix";

    # Hyprland 0.53.0 with matching hy3 hl0.53.0.1
    # (hy3 hasn't caught up to 0.54.0 yet)
    # hyprland.url = "github:hyprwm/Hyprland?ref=v0.53.0&submodules=1";

    # hy3.url = "github:outfoxxed/hy3?ref=hl0.53.0.1";
    # hy3.inputs.hyprland.follows = "hyprland";

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

    nix-compile.url = "github:sensenet-ai/nix-compile";
    nix-compile.inputs.nixpkgs.follows = "nixpkgs";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    # Bleeding-edge Emacs (master/31.x pgtk) + same-day MELPA snapshots. nixpkgs
    # only ships emacs 30.2; the overlay exposes pkgs.emacs-pgtk tracking the
    # emacs-31 dev branch. Consumed by modules/home/emacs to drive
    # mkHypermodernEmacs at 31. NOTE: ghostel's native module is rebuilt against
    # whatever emacs this resolves to, so a 31 bump recompiles ghostel-module.so.
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";

    # NativeLink remote-execution (Bazel/Buck2 RE). Provides the `nativelink`
    # binary for x86_64-linux and aarch64-linux; there is NO upstream NixOS
    # module, so modules/nixos/common/nativelink.nix hand-rolls the service.
    # Off by default; building from source is heavy unless you add
    # nativelink.cachix.org to substituters.
    nativelink.url = "github:TraceMachina/nativelink";
    nativelink.inputs.nixpkgs.follows = "nixpkgs";

    # attic binary cache — our fork (sensenet-ai) carrying the configurable
    # NAR chunk-prefetch fix (chunking.nar-prefetch). Upstream hardcodes prefetch
    # depth 2, which serializes chunk GETs against R2 (~150ms each) and makes
    # cold multi-GB pulls crawl. Its overlay (attic.overlays.default) provides the
    # patched pkgs.attic-server consumed by modules/nixos/attic.nix.
    # See docs/src/architecture/attic-prefetch.md.
    attic.url = "github:sensenet-ai/attic/b7r6/nar-prefetch-concurrency";
    attic.inputs.nixpkgs.follows = "nixpkgs";

    # straylight-prelude: the Buck2 prelude generator (sensenet-ai). Source of the
    # exact toolchain closure the RE workers run (llvm-git 22, ghc-with-packages,
    # rustc/cargo, lean4, python-env, nvidia-sdk, purescript) + buck2 itself, so
    # the operator devshell / VSCode see bit-identical tools to the CAS fleet.
    straylight-prelude.url = "github:sensenet-ai/straylight-prelude/main";
    straylight-prelude.inputs.nixpkgs.follows = "nixpkgs";
  };
}
