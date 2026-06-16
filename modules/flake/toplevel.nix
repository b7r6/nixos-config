{ inputs, self, ... }: {
  debug = true;

  imports = [
    inputs.nixos-unified.flakeModules.default
    inputs.nixos-unified.flakeModules.autoWire
    inputs.devshell.flakeModule
    # inputs.nix-compile.flakeModules.default  # Not available in new sensenet-ai version
    ./fmt.nix
    ./overlays.nix
    ./themes

    # ./impure-variants.nix  # TODO: needs different approach to avoid recursion
  ];

  # nix-compile static analysis configuration
  # NOTE: New sensenet-ai/nix-compile version does not provide flakeModules
  # Static analysis integration needs to be re-implemented manually if needed
  # nix-compile = {
  #   enable = false;
  #   profile = "strict";
  #   layout = "none";
  #   paths = [ "modules" "configurations" ];
  #   pre-commit.enable = true;
  # };

  perSystem =
    {
      self',
      pkgs,
      system,
      ...
    }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;

        config = {
          allowUnfree = true;
          allowUnfreePredicate = _: true;
        };

        overlays = [
          # Our overlay — this perSystem pkgs is what mkHomeConfiguration passes
          # into standalone homeConfigurations (and what devshells/packages use),
          # so applying it here gives standalone `nh home switch` the overlay
          # WITHOUT setting home-manager nixpkgs.overlays (which warns under
          # useGlobalPkgs). NixOS systems get it via modules/nixos/common/nix.nix.
          self.overlays.default

          inputs.devshell.overlays.default
          inputs.nix-vscode-extensions.overlays.default
        ];
      };

      devshells.default.imports = [ (pkgs.devshell.importTOML ../../devshell.toml) ];
      devshells.secrets.imports = [ (pkgs.devshell.importTOML ../../secrets/devshell.toml) ];

      # ── Apps ──────────────────────────────────────────────────────────────────

      apps.build-usb = {
        type = "app";
        program = "${self}/scripts/build-usb.sh";
      };

      packages = inputs.nixpkgs.lib.mkMerge [
        {
          default = self'.packages.activate;
          berkeley-mono = pkgs.callPackage ../home/themes/fonts/berkeley-mono { };
        }

        # ── USB Installer Images ─────────────────────────────────────────────────

        # Build with: nix build .#usb-aarch64-minimal
        #         or: nix build .#usb-x86_64-gnome

        (inputs.nixpkgs.lib.mkIf (system == "aarch64-linux") {
          usb-aarch64-minimal = inputs.nixos-generators.nixosGenerate {
            system = "aarch64-linux";
            format = "iso";
            modules = [
              self.nixosModules.dgx-spark
              "${self}/configurations/installer/aarch64-minimal.nix"
            ];
          };

          usb-aarch64-gnome = inputs.nixos-generators.nixosGenerate {
            system = "aarch64-linux";
            format = "iso";
            modules = [
              self.nixosModules.dgx-spark
              "${self}/configurations/installer/aarch64-gnome.nix"
            ];
          };
        })

        (inputs.nixpkgs.lib.mkIf (system == "x86_64-linux") {
          usb-x86_64-minimal = inputs.nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            format = "iso";
            modules = [ "${self}/configurations/installer/x86_64-minimal.nix" ];
          };

          usb-x86_64-gnome = inputs.nixos-generators.nixosGenerate {
            system = "x86_64-linux";
            format = "iso";
            modules = [ "${self}/configurations/installer/x86_64-gnome.nix" ];
          };
        })
      ];
    };
}
