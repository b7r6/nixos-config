{ pkgs, ... }:
{
  home.packages = with pkgs; [
    rubocop
    ruby_3_3
    solargraph
  ];
}
