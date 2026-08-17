{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.hyper-modern-nixos.kernel;
in
{
  options.hyper-modern-nixos.kernel = {
    enable = (lib.mkEnableOption "hyper-modern-nixos.kernel") // {
      default = true;
    };

    package = lib.mkOption {
      type = lib.types.raw;
      default = pkgs.linuxPackages_7_0;

      description = ''
        Linux kernel package.
      '';
    };
  };

  config = lib.mkIf cfg.enable { boot.kernelPackages = lib.mkDefault cfg.package; };
}
