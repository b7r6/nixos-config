{
  config,
  lib,
  pkgs,
  ...
}:
let
  termType = "xterm-256color";
in
{
  programs.bash = {
    enable = true;
    enableCompletion = true;
  };
}
