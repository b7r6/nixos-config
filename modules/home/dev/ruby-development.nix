{ pkgs, ... }:
{
  home.packages = with pkgs; [
    rubocop
    ruby_3_1
    solargraph
  ];
}
