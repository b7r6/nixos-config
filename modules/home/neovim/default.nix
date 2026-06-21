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

      # Force a BLINKING BLOCK cursor in every mode (no beam in insert, no
      # underline in replace). `a:` applies to all modes; the blink timing makes
      # it blink, and `guicursor` is what neovim uses to emit DECSCUSR escapes to
      # the terminal — so this is the layer that would otherwise override
      # ghostty's block. blinkwait/on/off in ms.
      extraConfig = ''
        set guicursor=a:block-blinkwait500-blinkon500-blinkoff500
      '';
    };
  };
}
