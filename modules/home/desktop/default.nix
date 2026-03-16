{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.desktop;
in
{
  options.hyper-modern-nixos.desktop = {
    enable = lib.mkEnableOption "desktop applications and tools";

    browsers.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable web browsers (Firefox, Brave, Chromium)";
    };

    fileManager.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable file manager (Nemo)";
    };

    audio.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable audio control tools (pavucontrol)";
    };

    communication.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable communication apps (Slack, etc.)";
    };

    passwordManager.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable 1Password GUI and CLI";
    };
  };

  config = lib.mkIf cfg.enable {
    fonts.fontconfig.enable = true;

    home.packages =
      with pkgs;
      lib.flatten [
        (lib.optionals cfg.passwordManager.enable [
          _1password-cli
          _1password-gui-beta
        ])

        (lib.optionals cfg.browsers.enable [
          brave
          chromium
          firefox
        ])

        (lib.optional cfg.fileManager.enable nemo)
        (lib.optional cfg.audio.enable pavucontrol)

        (lib.optionals cfg.communication.enable [
          slack-term
          spotify-cli-linux
        ])
      ];
  };
}
