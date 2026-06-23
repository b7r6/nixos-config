# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                        // hyper-modern-nixos // flake // usb
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# USB installer images (nixos-generators) + the build-usb app.
#
# Build with: nix build .#usb-aarch64-minimal
#         or: nix build .#usb-x86_64-gnome
{ inputs, self, ... }: {
  perSystem = { system, ... }: {
    apps.build-usb = {
      type = "app";
      program = "${self}/scripts/build-usb.sh";
    };

    packages = inputs.nixpkgs.lib.mkMerge [
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
