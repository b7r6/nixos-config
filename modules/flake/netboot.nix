# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                        // hyper-modern-nixos // flake // netboot
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The Jetson netboot/kexec kit. Builds the RAM installer
# (configurations/installer/aarch64-jetson-netboot.nix) and packages it for the
# two delivery mechanisms that actually work on this hardware:
#
#   netboot-jetson-kexec    kernel + initrd + kexec.sh — the proven beachhead:
#                           kexec from the running system. kexec.sh carries the
#                           exact cmdline that survives (see below).
#   netboot-jetson-memdisk  a single bootaa64.efi with GRUB + kernel + initrd
#                           embedded via memdisk — for firmware PXE/TFTP or
#                           UEFI HTTP boot where a real broadcast domain or
#                           private wire exists. Nothing after the transfer
#                           needs network, which is the whole trick.
#
# Hard-won constraints (verified on filament, 2026-08-06 — see the operations
# chapter for the full post-mortem):
#   - the kexec cmdline MUST be trimmed: the stock jetpack cmdline's
#     earlycon=tegra_utc / UART console params wedge a kexec'd kernel before
#     console-up. init= + panic=30 + console=tty0 + clk_ignore_unused, nothing
#     else.
#   - firmware PXE and iPXE snp.efi are dead on the devkit RJ45 (RTL8126): the
#     firmware enumerates the NIC (creates PXE boot entries) but has no working
#     driver for it. Do not spend another evening there.
#
# Build:  nix build .#netboot-jetson-kexec
# Drive:  nix run  .#kexec-jetson -- [user@host]     (default b7r6@filament)
#
{
  inputs,
  self,
  config,
  ...
}:
let
  specialArgs = {
    flake = { inherit self inputs config; };
  };

  # nixpkgs-jetson, not the fleet nixpkgs — same CUDA-manifest constraint as
  # the filament host (see flake.nix)
  netbootSystem = inputs.nixpkgs-jetson.lib.nixosSystem {
    inherit specialArgs;
    modules = [
      { nixpkgs.hostPlatform = "aarch64-linux"; }
      "${self}/configurations/installer/aarch64-jetson-netboot.nix"
    ];
  };

  nb = netbootSystem.config.system.build;
in
{
  perSystem = { pkgs, system, ... }: {
    packages = inputs.nixpkgs.lib.mkMerge [
      (inputs.nixpkgs.lib.mkIf (system == "aarch64-linux") {

        netboot-jetson-kexec =
          pkgs.runCommand "netboot-jetson-kexec" { initPath = "${nb.toplevel}/init"; }
            ''
              mkdir -p $out
              ln -s ${nb.kernel}/Image $out/Image
              ln -s ${nb.netbootRamdisk}/initrd $out/initrd

              cat > $out/kexec.sh <<EOF
              #!/usr/bin/env bash
              # kexec into the filament netboot installer.
              #
              # PROVEN cmdline (2026-08-06): the stock jetpack cmdline's
              # earlycon=tegra_utc / UART console params wedge a kexec'd
              # kernel before console-up. Keep this line trimmed exactly so.
              set -euo pipefail
              DIR="\$(cd "\$(dirname "\$0")" && pwd)"
              kexec --load "\$DIR/Image" --initrd="\$DIR/initrd" \
                --command-line="init=$initPath panic=30 console=tty0 loglevel=7 clk_ignore_unused"
              sync
              # -e severs the session immediately; the box returns as
              # filament-netboot on its DHCP lease in ~1 minute
              exec kexec -e
              EOF
              chmod +x $out/kexec.sh
            '';

        netboot-jetson-memdisk =
          pkgs.runCommand "netboot-jetson-memdisk" { nativeBuildInputs = [ pkgs.grub2_efi ]; }
            ''
              mkdir -p $out

              cat > grub.cfg <<EOF
              insmod normal
              insmod linux
              insmod gzio
              insmod efi_gop
              set timeout=3
              set default=0
              menuentry "filament netboot installer" {
                  linux (memdisk)/kernel init=${nb.toplevel}/init panic=30 console=tty0 loglevel=7 clk_ignore_unused
                  initrd (memdisk)/initrd
              }
              EOF

              grub-mkstandalone \
                --format=arm64-efi \
                --output=$out/bootaa64.efi \
                --modules="linux normal boot gzio efi_gop" \
                --locales= \
                --fonts= \
                "/boot/grub/grub.cfg=grub.cfg" \
                "/kernel=${nb.kernel}/Image" \
                "/initrd=${nb.netbootRamdisk}/initrd"
            '';
      })
    ];

    apps.kexec-jetson = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "kexec-jetson";
          text = ''
            # Build the kexec bundle, push it to the target, and fire.
            # The target returns as filament-netboot (root ssh, admin keys)
            # on its DHCP lease; drive the re-image with
            #   nixos-anywhere --flake .#filament --phases disko,install \
            #     --extra-files <host-key-tree> root@<target>
            target="''${1:-b7r6@filament}"

            bundle=$(nix build "${self}#netboot-jetson-kexec" --no-link --print-out-paths)

            echo "pushing netboot bundle to $target"
            scp "$bundle/Image" "$bundle/initrd" "$bundle/kexec.sh" "$target:/tmp/"

            echo "kexec'ing $target — the session will drop; the box returns as filament-netboot in ~1 min"
            ssh "$target" 'sudo bash /tmp/kexec.sh' || true
          '';
        }
      );
    };
  };
}
