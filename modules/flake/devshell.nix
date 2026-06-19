# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                       // hyper-modern-nixos // flake/devshell
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Auto-load the operator's user secrets into the DEFAULT dev shell via
# agenix-shell. On shell entry each secret is decrypted (with the operator's
# SSH identities) to a tmpfs under $XDG_RUNTIME_DIR and exported as:
#
#   <NAME>        = the decrypted contents          (great for tokens)
#   <NAME>_PATH   = path to the decrypted tmpfs file (great for file-shaped
#                   secrets like netrc / rclone.conf)
#
# SCOPE: only the things the operator has a license to — the user secrets under
# secrets/agenix/users/b7r6/. Machine secrets (restic password, atticd RS256,
# R2 env files) are deliberately NOT loaded into the interactive shell; they
# belong to systemd services on the hosts, decrypted by host keys at activation.
# (This is the one place straylight-infra overreaches — it blanket-loads every
# .age including machine secrets into every shell. We don't.)
#
# The agenix admin commands (edit/rekey/rotate) live in the separate `secrets`
# devshell (secrets/devshell.toml); this module only handles env auto-loading.
{ inputs, ... }: {
  perSystem =
    { system, ... }:
    let
      # Decrypt with whichever of the operator's keys is present. agenix-shell
      # tries each identity in turn, so listing all three is harmless.
      identityPaths = [
        "$HOME/.ssh/id_ed25519"
        "$HOME/.ssh/id_ed25519_b7r6"
        "$HOME/.ssh/id_ed25519_yubikey"
      ];

      userSecrets = ../../secrets/agenix/users/b7r6;

      # name -> { file }. Names become the exported env-var names. Keep them
      # conventional (UPPER_SNAKE) so downstream tools pick them up directly.
      secrets = {
        HF_TOKEN.file = userSecrets + "/hf-token.age";
        ATUIN_KEY.file = userSecrets + "/atuin-key.age";
        NETRC.file = userSecrets + "/netrc.age";
        RCLONE_CONF.file = userSecrets + "/rclone-conf.age";
      };

      installSecrets = inputs.agenix-shell.lib.installationScript system {
        inherit identityPaths secrets;
      };
    in
    {
      # Fold the decrypt-and-export hook into the default devshell's startup.
      # numtide/devshell runs startup entries on shell entry, after the TOML
      # commands/packages are set up.
      devshells.default.devshell.startup.agenix-shell.text = ''
        source ${installSecrets}/bin/install-agenix-shell
      '';
    };
}
