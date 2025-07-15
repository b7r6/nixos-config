{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.common
    ./themes
    ./wayland
  ];

  hypermodern.nixos.themes = {
    enable = true;
    theme = "ono-sendai-blue";
    variant = "chiba";

    display = {
      profile = "samsung-e6";
      highDPI = true;
      width = 3840;
      height = 2400;
    };

    overrides = {
      fontSizes = {
        desktop = 14;
        applications = 14;
        terminal = 14;
        popups = 14;
      };
    };
  };
}
