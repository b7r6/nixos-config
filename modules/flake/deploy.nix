# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                // hypermodern // nix // deploy
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# `nix run .#deploy-fleet [-- host...]` — deploy the whole fleet (or named
# hosts), including self. Encodes the patterns we learned the hard way:
#   - self (matches the host's networking.hostName): local
#     `nixos-rebuild switch`.
#   - remote, SAME arch as the builder: build the closure HERE (attic cache
#     hit), `nix copy` it over the tailnet, register it as the system profile
#     generation (so it PERSISTS across reboot + installs the bootloader
#     entry), then a BACKGROUNDED switch-to-configuration — because activation
#     can restart tailscaled and drop the ssh-over-tailnet session mid-switch
#     (the tailscale authKeyFile safety net brings the box back).
#     Backgrounding avoids a wedged session.
#   - remote, DIFFERENT arch (e.g. aarch64 shimmer from an x86_64 builder):
#     build + switch ON THE HOST over ssh (it pulls cached paths from attic);
#     no cross-build/emulation here.
# test-vm is excluded (it's a VM, not a real host).
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{ self, ... }: {
  perSystem = { pkgs, ... }: {
    apps.deploy-fleet =
      let
        deployable = pkgs.lib.filterAttrs (n: _: n != "test-vm") self.nixosConfigurations;
        # "attrName:system:hostName" lines baked in at build time (no runtime nix
        # eval). hostName is the host's real networking.hostName so self-detection
        # is correct even if it ever diverges from the flake attr name.
        hostLines = pkgs.lib.concatStringsSep "\n" (
          pkgs.lib.mapAttrsToList (
            name: cfg: "${name}:${cfg.pkgs.stdenv.hostPlatform.system}:${cfg.config.networking.hostName}"
          ) deployable
        );
      in
      {
        type = "app";
        program = pkgs.lib.getExe (
          pkgs.writeShellApplication {
            name = "deploy-fleet";
            runtimeInputs = [
              pkgs.openssh
              pkgs.nixos-rebuild
              pkgs.nix
            ];
            text = ''
              builder_system="${pkgs.stdenv.hostPlatform.system}"
              self_host="$(hostname)"
              flake="''${FLAKE:-.}"
              remote_flake_dir="''${REMOTE_FLAKE_DIR:-src/nixos-config}"
              system_profile="/nix/var/nix/profiles/system"

              # attrName:system:hostName table baked at build time.
              all_hosts=$(printf '%s\n' "${hostLines}")

              # Args = explicit host list (attr names); else every deployable host.
              if [ "$#" -gt 0 ]; then
                targets=("$@")
              else
                mapfile -t targets < <(printf '%s\n' "$all_hosts" | cut -d: -f1)
              fi

              # Exact-match lookup into the baked table (no regex / prefix bugs).
              lookup() { # $1=attrName $2=field(2=system,3=hostName)
                printf '%s\n' "$all_hosts" | while IFS=: read -r n s hn; do
                  [ "$n" = "$1" ] || continue
                  case "$2" in 2) printf '%s' "$s" ;; 3) printf '%s' "$hn" ;; esac
                  break
                done
              }

              fail=0
              for host in "''${targets[@]}"; do
                system=$(lookup "$host" 2)
                hostname_of=$(lookup "$host" 3)
                if [ -z "$system" ]; then
                  echo "// deploy // SKIP $host (not a deployable host)" >&2
                  fail=1; continue
                fi

                echo ""
                echo "// deploy // ━━━ $host ($system) ━━━"

                if [ "$hostname_of" = "$self_host" ]; then
                  echo "// deploy // $host = self → local switch"
                  sudo nixos-rebuild switch --flake "$flake#$host" || fail=1

                elif [ "$system" = "$builder_system" ]; then
                  echo "// deploy // $host = remote (same arch) → build here, copy, register+bg switch"
                  # Build the toplevel via `nix build` (stable --print-out-paths),
                  # NOT `nixos-rebuild build` — nixos-rebuild-ng (the Python
                  # rewrite) dropped --print-out-paths, and we want the system
                  # closure path to nix-copy + register on the remote anyway.
                  if ! out=$(nix build --no-link --print-out-paths "$flake#nixosConfigurations.$host.config.system.build.toplevel" | tail -1); then
                    echo "// deploy // build FAILED for $host" >&2; fail=1; continue
                  fi
                  if [ -z "$out" ]; then echo "// deploy // build produced no path for $host" >&2; fail=1; continue; fi
                  if ! nix copy --to "ssh://$host" "$out"; then
                    echo "// deploy // copy FAILED for $host" >&2; fail=1; continue
                  fi
                  # Register the closure as the system profile generation FIRST
                  # (synchronously — so it survives reboot and switch-to-configuration
                  # installs the bootloader entry from it), THEN background ONLY the
                  # activation: the tailscaled restart during activation can drop
                  # this ssh session; the authKeyFile safety net reconnects the box.
                  # The `{ … & }` grouping keeps nix-env in the foreground while
                  # detaching switch-to-configuration.
                  # SC2029: client-side expansion of $out/$host/$system_profile is INTENDED.
                  # shellcheck disable=SC2029
                  ssh "$host" "sudo nix-env -p $system_profile --set $out && { sudo nohup $out/bin/switch-to-configuration switch >/tmp/deploy-$host.log 2>&1 & } && echo '// deploy // $host switch dispatched (log: /tmp/deploy-$host.log)'" || fail=1

                else
                  echo "// deploy // $host = remote (cross-arch $system) → build+switch ON the host"
                  # SC2029: client-side expansion of $remote_flake_dir/$host is INTENDED.
                  # shellcheck disable=SC2029
                  ssh "$host" "cd \"$remote_flake_dir\" && git pull --ff-only && sudo nixos-rebuild switch --flake .#$host" || fail=1
                fi
              done

              echo ""
              if [ "$fail" -eq 0 ]; then
                echo "// deploy // all targets dispatched OK"
              else
                echo "// deploy // one or more targets had issues (see above)" >&2
                exit 1
              fi
            '';
          }
        );
      };
  };
}
