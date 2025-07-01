{ pkgs, ... }:
{
  home.packages = with pkgs; [
    basedpyright
    pyright
    ruff
    uv
  ];
}
