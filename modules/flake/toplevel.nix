{ inputs, self, ... }: {
  debug = true;

  imports = [
    inputs.devshell.flakeModule
    ./fmt.nix
    ./overlays.nix
    ./devshell.nix
    ./docs.nix
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

    # `nix run .#nativelink-render` — render the typed Dhall fleet config to the
    # committed nativelink/out/<host>.json (one per fleet host). Dhall is the
    # source of truth; committed JSON is IFD-free. Run after editing nativelink/*.dhall.
    apps.nativelink-render = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "nativelink-render";
          runtimeInputs = [
            pkgs.dhall-json
            pkgs.jq
          ];
          text = ''
            root="$(git rev-parse --show-toplevel)"
            cd "$root/nativelink"
            mkdir -p out
            dhall-to-json --file render-all.dhall | jq -c '.[]' | while read -r item; do
              host=$(echo "$item" | jq -r .host)
              echo "$item" | jq -r .json | jq . > "out/$host.json"
              echo "// nativelink // rendered out/$host.json"
            done
            echo "// nativelink // done (commit nativelink/out/*.json)"
          '';
        }
      );
    };

    # `nix run .#nativelink-check` — verify committed out/*.json match the Dhall.
    apps.nativelink-check = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "nativelink-check";
          runtimeInputs = [
            pkgs.dhall-json
            pkgs.jq
            pkgs.diffutils
          ];
          text = ''
            root="$(git rev-parse --show-toplevel)"
            cd "$root/nativelink"
            # Render to a temp dir and diff the whole tree — avoids the
            # subshell-`exit` gotcha (a `while | read` pipeline runs in a subshell,
            # so an `exit 1` inside it can't fail the script).
            tmp="$(mktemp -d)"
            trap 'rm -rf "$tmp"' EXIT
            dhall-to-json --file render-all.dhall | jq -c '.[]' > "$tmp/items"
            while read -r item; do
              host=$(echo "$item" | jq -r .host)
              echo "$item" | jq -r .json | jq . > "$tmp/$host.json"
            done < "$tmp/items"
            ok=1
            for f in out/*.json; do
              host="$(basename "$f" .json)"
              if ! diff -u "$f" "$tmp/$host.json" >/dev/null 2>&1; then
                echo "// nativelink // STALE: $f (run: nix run .#nativelink-render)" >&2
                ok=0
              fi
            done
            if [ "$ok" -eq 1 ]; then
              echo "// nativelink // out/*.json in sync with the Dhall fleet"
            else
              exit 1
            fi
          '';
        }
      );
    };

    # `nix run .#topology-render` — render the Dhall topology registry to the
    # committed registry/registry.json. Dhall is the source of truth; the JSON is
    # a committed artifact (no import-from-derivation, so `nix flake check` works).
    # Run after editing registry/*.dhall, then commit the regenerated JSON.
    apps.topology-render = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "topology-render";
          runtimeInputs = [ pkgs.dhall-json ];
          text = ''
            root="$(git rev-parse --show-toplevel)"
            cd "$root/registry"
            dhall-to-json --file hosts.dhall > registry.json
            echo "// topology // rendered registry/registry.json (commit it)"
          '';
        }
      );
    };

    # `nix run .#topology-check` — verify the committed registry.json is in sync
    # with the Dhall source (CI/pre-commit guard against a stale artifact).
    apps.topology-check = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "topology-check";
          runtimeInputs = [
            pkgs.dhall-json
            pkgs.diffutils
          ];
          text = ''
            root="$(git rev-parse --show-toplevel)"
            cd "$root/registry"
            if ! dhall-to-json --file hosts.dhall | diff -u registry.json - ; then
              echo "// topology // registry.json is STALE — run: nix run .#topology-render" >&2
              exit 1
            fi
            echo "// topology // registry.json is in sync with hosts.dhall"
          '';
        }
      );
    };

    # `nix run .#restic-init -- <host>` — trigger the one-time, idempotent
    # restic-backups-init.service on a host over the tailnet (or locally). The
    # unit uses the host's own agenix-decrypted password/env, so there's nothing
    # to pass but the hostname.
    apps.restic-init = {
      type = "app";
      program = pkgs.lib.getExe (
        pkgs.writeShellApplication {
          name = "restic-init";
          runtimeInputs = [ pkgs.openssh ];
          text = ''
            host="''${1:-}"
            if [ -z "$host" ]; then
              echo "usage: nix run .#restic-init -- <host>" >&2
              echo "  triggers restic-backups-init.service on <host> (idempotent)." >&2
              exit 1
            fi
            if [ "$host" = "$(hostname)" ]; then
              sudo systemctl start --wait restic-backups-init.service
              sudo journalctl -u restic-backups-init.service -n 20 --no-pager
            else
              # shellcheck disable=SC2029
              ssh "$host" 'sudo systemctl start --wait restic-backups-init.service \
                && sudo journalctl -u restic-backups-init.service -n 20 --no-pager'
            fi
          '';
        }
      );
    };

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

    # ── Checks (NixOS VM tests) ─────────────────────────────────────────────────
    # Linux-only (nixosTest needs a Linux builder).
    checks = inputs.nixpkgs.lib.optionalAttrs (system == "x86_64-linux") {
      attic-cache = import ../../checks/attic-cache.nix { inherit pkgs inputs; };
      backup-restic = import ../../checks/backup-restic.nix { inherit pkgs inputs; };
      clickhouse-keeper = import ../../checks/clickhouse-keeper.nix { inherit pkgs; };
      clickhouse-server = import ../../checks/clickhouse-server.nix { inherit pkgs; };
      otel-ingest = import ../../checks/otel-ingest.nix { inherit pkgs; };
    };

    packages = inputs.nixpkgs.lib.mkMerge [
      {
        berkeley-mono = pkgs.callPackage ../home/themes/fonts/berkeley-mono { };
        default = pkgs.callPackage ../home/themes/fonts/berkeley-mono { };
        ono-sendai-generator = pkgs.callPackage ../../packages/ono-sendai-generator { };
        clickhouse-keeper-smoke-test = pkgs.callPackage ../../packages/clickhouse-keeper-smoke-test { };
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
