{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # future-looking typescript environment...
    biome
    bun
    typescript

    # mandatory current typescript support...
    nodePackages.fixjson
    nodePackages.nodejs
    nodePackages.prettier
    nodePackages.typescript-language-server
    nodePackages.yarn
  ];
}
