{

  config,
  lib,
  pkgs,
  ...
}:
{
  nix = {
    settings = {
      substituters = [
        "https://cache.nixos.org"
        "https://ps-v4-public.cachix.org"
        "https://nix-community.cachix.org"
        "https://hyprland.cachix.org"
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "ps-v4-public.cachix.org-1:+sBXoNcPK3310QTXFk55rZFOHZdoP6rLetLYkDkEbp4="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };

    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  services.cachix-agent = {
    enable = true;

    # TODO[b7r6]: configure vault...
    # name = "your-cache-name";
    # credentialsFile = "/etc/cachix-agent.token";
  };

}
