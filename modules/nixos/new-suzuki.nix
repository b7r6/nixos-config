{ config, lib, ... }:
let
  cfg = config.hyper-modern-nixos.new-suzuki;
in
{
  options.hyper-modern-nixos.new-suzuki = {
    enable = lib.mkEnableOption "the complete New Suzuki Quickshell desktop";

    user = lib.mkOption {
      type = lib.types.str;
      default = "b7r6";
      description = "Home Manager user that receives the desktop configuration.";
    };

    exclusive = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Let Quickshell replace the bar, launcher, notifications, and key bindings.";
    };

    cudaField.enable = lib.mkEnableOption "the CUDA-backed wintermute field presenter";

    battery.enable = lib.mkEnableOption "UPower support for the shell battery widget";

    register = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "Initial affluent (0.0) to facility (1.0) visual register.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.upower.enable = cfg.battery.enable;

    home-manager.users.${cfg.user}.hyper-modern-nixos.new-suzuki = {
      enable = true;
      inherit (cfg) exclusive register;
      cudaField.enable = cfg.cudaField.enable;
    };
  };
}
