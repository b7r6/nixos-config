{ config, lib, ... }:
let
  cfg = config.hyper-modern-nixos.neovim;
in
{
  options.hyper-modern-nixos.neovim = {
    enable = lib.mkEnableOption "Neovim editor configuration";

    defaultEditor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Set Neovim as the default editor";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      inherit (cfg) defaultEditor;
      withRuby = false;
      withPython3 = false;
      viAlias = true;
      vimAlias = true;

      # Blinking block in every mode (no beam in insert, no underline in
      # replace). `guicursor` is how neovim asserts cursor style: in the TUI it
      # compiles to DECSCUSR escapes, which tmux passes through (Ss/Se
      # overrides, see modules/home/shell) and which override the terminal's
      # idle default until neovim exits and resets.
      # n.b. the millisecond values do NOT survive translation to DECSCUSR —
      # any nonzero blink params select the *blinking* variant, none selects
      # steady; the terminal blinks at its own rate either way.
      extraConfig = ''
        set guicursor=a:block-blinkwait500-blinkon500-blinkoff500
      '';
    };
  };
}
