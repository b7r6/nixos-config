{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # future-looking typescript environment...
    biome
    bun
    typescript

    # mandatory current typescript support...
    nodePackages.fixjson
    nodePackages_latest.nodejs
    nodePackages_latest.prettier
    nodePackages_latest.typescript-language-server
    nodePackages_latest.yarn
  ];
}
