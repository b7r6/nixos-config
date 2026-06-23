# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                       // hyper-modern-nixos // secrets/flake
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The secrets administration subsystem: every agenix/passage management command
# is a real, shellcheck/shfmt-clean script under ./sh, wrapped as a
# `writeShellApplication` with pinned runtimeInputs, and exposed BOTH as:
#
#   - packages in the `secrets` devShell  (nix develop .#secrets)
#   - standalone flake apps               (nix run .#rekey-secrets)
#
# Each command is git-root-aware: it locates the repo's secrets/ directory and
# cd's there first, so `agenix -r` etc. find the RULES file (secrets.nix) and
# the .age tree no matter where you invoke it from.
#
# This is the operator/admin surface. Auto-loading the operator's USER secrets
# into the *default* devshell env (HF_TOKEN, NETRC_PATH, …) is a separate
# concern handled by modules/flake/devshell.nix via agenix-shell.
{ inputs, ... }: {
  perSystem =
    { pkgs, system, ... }:
    let
      agenix = inputs.agenix.packages.${system}.default;

      runtimeInputs = [
        agenix
        pkgs.age
        pkgs.rage
        pkgs.ssh-to-age
        pkgs.openssh # ssh-keyscan
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.gawk
        pkgs.jq
      ];

      # name -> script source. Names become both devShell command names and
      # flake app names (`nix run .#<name>`).
      scripts = {
        list-secrets = ./sh/list-secrets.sh;
        view-secret = ./sh/view-secret.sh;
        edit-secret = ./sh/edit-secret.sh;
        new-secret = ./sh/new-secret.sh;
        rotate-secret = ./sh/rotate-secret.sh;
        rekey-secrets = ./sh/rekey-secrets.sh;
        init-secrets = ./sh/init-secrets.sh;
        validate-secrets = ./sh/validate-secrets.sh;
        scan-host-key = ./sh/scan-host-key.sh;
        init-passage = ./sh/init-passage.sh;
        secrets-usage = ./sh/secrets-usage.sh;
      };

      # Wrap a script so it always runs from the repo's secrets/ directory and
      # points agenix at the RULES file there. Falls back to the script's own
      # location if not in a git tree.
      mkSecretApp =
        name: script:
        pkgs.writeShellApplication {
          inherit name runtimeInputs;
          text = ''
            if git rev-parse --show-toplevel >/dev/null 2>&1; then
              SECRETS_DIR="$(git rev-parse --show-toplevel)/secrets"
            else
              SECRETS_DIR="$(dirname "$(readlink -f "$0")")/../../secrets"
            fi

            if [ -d "$SECRETS_DIR" ]; then
              cd "$SECRETS_DIR"
            else
              echo "warning: could not find secrets/ (looked at: $SECRETS_DIR)" >&2
            fi

            # agenix reads recipients from this RULES file.
            export RULES="$SECRETS_DIR/secrets.nix"

            ${builtins.readFile script}
          '';
        };

      apps' = pkgs.lib.mapAttrs mkSecretApp scripts;
    in
    {
      devShells.secrets = pkgs.mkShellNoCC {
        name = "hypermodern-secrets";
        packages = builtins.attrValues apps' ++ [
          agenix
          pkgs.age
          pkgs.rage
          pkgs.ssh-to-age
          pkgs.passage
          pkgs.age-plugin-yubikey
          pkgs.yubikey-manager
        ];
        shellHook = ''
          ${apps'.secrets-usage}/bin/secrets-usage
        '';
      };

      apps = pkgs.lib.mapAttrs (name: app: {
        type = "app";
        program = "${app}/bin/${name}";
      }) apps';
    };
}
