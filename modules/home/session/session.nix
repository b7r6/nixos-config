_: {
  home.sessionVariables = {
    PATH = "$HOME/.local/bin:$PATH";
    EDITOR = "nvim";
    NIXOS_OZONE_WL = "1";

    # TODO[b7r6]: do arbitrary things to make nix obey...
    NIXPKGS_ALLOW_UNFREE = "1";
  };
}
