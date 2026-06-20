{ inputs, self, ... }: {
  debug = true;

  imports = [
    inputs.devshell.flakeModule
    ./fmt.nix
    ./overlays.nix
    ./devshell.nix
    ./themes

    # secrets administration subsystem (devShells.secrets + flake apps)
    ../../secrets
  ];

  perSystem = { pkgs, system, ... }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;

      config = {
        allowUnfree = true;
        allowUnfreePredicate = _: true;
      };

      overlays = [
        # Our overlay — this perSystem pkgs is what standalone homeConfigurations
        # use (and what devshells/packages use), so applying it here gives
        # standalone `nh home switch` the overlay WITHOUT setting
        # home-manager nixpkgs.overlays (which warns under useGlobalPkgs).
        # NixOS systems get it via modules/nixos/nix.nix.
        self.overlays.default

        inputs.devshell.overlays.default
        inputs.nix-vscode-extensions.overlays.default

        # emacs-pgtk -> 31.x (master). modules/home/emacs uses it.
        inputs.emacs-overlay.overlays.default
      ];
    };

    devshells.default.imports = [ (pkgs.devshell.importTOML ../../devshell.toml) ];
    # devShells.secrets is provided by ../../secrets (flake-parts module) as a
    # plain mkShell with writeShellApplication-wrapped commands + flake apps.

    # ── Apps ──────────────────────────────────────────────────────────────────

    apps.build-usb = {
      type = "app";
      program = "${self}/scripts/build-usb.sh";
    };

    # ── Checks (NixOS VM tests) ─────────────────────────────────────────────────
    # Linux-only (nixosTest needs a Linux builder).
    checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      attic-cache = import ../../checks/attic-cache.nix { inherit pkgs self; };
    };

    packages = inputs.nixpkgs.lib.mkMerge [
      {
        berkeley-mono = pkgs.callPackage ../home/themes/fonts/berkeley-mono { };
        default = pkgs.callPackage ../home/themes/fonts/berkeley-mono { };
        ono-sendai-generator = pkgs.callPackage ../../packages/ono-sendai-generator { };
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
