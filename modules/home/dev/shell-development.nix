{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bash-completion
    bash-language-server
    beautysh
    shellcheck
    shfmt
  ];
}
