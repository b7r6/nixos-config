{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.hypermodern.nixos.audio.bitgwig;
in
{
  options.hypermodern.nixos.audio.bitwig = {
    enable = mkEnableOption "// hypermodern // nixos // audio // bitwig";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
    ];
  };
}
