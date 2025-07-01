{ inputs, ... }:
let
  flake-options =
    let
      prefix = ''/flakeref#'';
      options = ''debug.options'';
    in
    ''${prefix} ${options}'';

  nixos-options =
    let
      nixpkgs-import = ''(let pkgs = import "${inputs.nixpkgs}" { };'';
      modules-import = ''in (pkgs.lib.evalModules { modules =  (import "${inputs.nixpkgs}/nixos/modules/module-list.nix") ++ '';
      options-clause = ''[ ({...}: { nixpkgs.hostPlatform = builtins.currentSystem;} ) ] ; })).options'';
    in
    ''${nixpkgs-import} ${modules-import} ${options-clause}'';

  devenv-module-options =
    let
      nixpkgs-import = ''(let pkgs = import "${inputs.nixpkgs}" { };'';
      lib-import = ''lib = pkgs.lib;'';
      flake-parts-lib-import = ''flake-parts-lib = (import "${inputs.flake-parts}/lib/modules.nix") lib;'';
      modules-eval = ''in ((import "${inputs.devenv}/lib/flake-module.nix") { inherit inputs lib flake-parts-lib; }).options'';
    in
    ''${nixpkgs-import} ${lib-import} ${flake-parts-lib-import} ${modules-eval}'';

  home-manager-options =
    let
      nixpkgs-import = ''(let pkgs = import "${inputs.nixpkgs}" { };'';
      stdlib-import = ''lib = import "${inputs.home-manager}/modules/lib/stdlib-extended.nix" pkgs.lib;'';
      modules-clause = ''in (lib.evalModules { modules =  (import "${inputs.home-manager}/modules/modules.nix")'';
      inherit-clause = ''{ inherit lib pkgs; check = false; }; })).options'';
    in
    ''${nixpkgs-import} ${stdlib-import} ${modules-clause} ${inherit-clause}'';

  nixdConfig = {
    formatting.command = "nixpkgs-fmt";

    eval = {
      target = {
        args = [
          "--expr"
          "import <nixpkgs> {}"
          # "with import <nixpkgs> { }; callPackage ./somePackage.nix { }"
        ];
      };

      depth = 64; # force thunks to depth...
    };

    options = {
      enable = true;

      target = {
        args = [ ];
        inherit
          flake-options
          nixos-options
          home-manager-options
          devenv-module-options
          ;
      };
    };
  };
in
{
  perSystem =
    { pkgs, ... }:
    let

      # Minimal configuration
      # Convert to JSON and write to a file
      nixdConfigFile = pkgs.writeTextFile {
        name = "nixd-config.json";
        text = builtins.toJSON nixdConfig;
      };

      # Validate the JSON with jq to ensure it's correct
      validatedConfig = pkgs.runCommand "validated-nixd-config.json" { } ''
        ${pkgs.jq}/bin/jq . ${nixdConfigFile} > $out
      '';

      # Create the wrapper script with explicit debugging
      nixd-with-config = pkgs.writeShellScriptBin "nixd" ''
        CONFIG="${validatedConfig}"
        echo "Using config file: $CONFIG" >&2
        echo "Config contents:" >&2

        cat "$CONFIG" >&2
        exec ${pkgs.nixd}/bin/nixd --config "$CONFIG" "$@"
      '';

    in
    {
      devShells.default = pkgs.mkShell {
        name = "dev-v4";
        meta.description = "DEV // V4";
        pacakges = [ nixd-with-config ];

        shellHook = ''
          export NIX_CONFIG="experimental-features = nix-command flakes"
        '';
      };
    };
}
