{
  flake,
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (flake) inputs;

  themes = {
    ono-sendai = import ./ono-sendai-blue.nix;
  };

  themeVariants = with builtins; concatLists (attrValues (mapAttrs (_: attrNames) themes));

  # # TODO[b7r6]: Replace this with a proper fetchFromGitHub or similar approach
  # # This is a temporary solution until we have a proper way to handle Berkeley Mono
  # berkeley-mono = pkgs.stdenv.mkDerivation {
  #   name = "berkeley-mono-font";
  #   src = ./.;

  #   dontUnpack = true;
  #   installPhase = ''
  #     mkdir -p $out/share/fonts/opentype
  #     cp ${./berkeley-mono-semi-bold.otf} $out/share/fonts/opentype/
  #   '';
  # };

  berkeley-mono = pkgs.callPackage ./fonts/berkeley-mono { };

  monoFont = {
    package = berkeley-mono;
    name = "Berkeley Mono Medium";
  };
  
  cfg = config.hyper-modern-nixos.themes;
in
{
  imports = [ inputs.stylix.homeManagerModules.stylix ];

  options.hyper-modern-nixos.themes = {
    enable = lib.mkEnableOption "hyper-modern-nixos.themes" // {
      default = true;
    };

    theme = lib.mkOption {
      type = lib.types.enum [ "ono-sendai" ];
      default = "ono-sendai";
      description = "theme family";
    };

    variant = lib.mkOption {
      type = lib.types.enum themeVariants;
      default = "chiba";
      description = "theme family";
    };

    palette = lib.mkOption {
      type = lib.types.attrs;
      description = "The base16 theme palette with hashtags for use in configurations";
      internal = true;
      readOnly = true;
      default = themes.${cfg.theme}.${cfg.variant}.palette;
    };
  };

  config = lib.mkIf cfg.enable {

    stylix = {
      enable = true;
      autoEnable = true;

      image = ./hyper-modern-nixos-wallpaper-0x01.png;

      base16Scheme = themes.${cfg.theme}.${cfg.variant};

      fonts = {
        monospace = monoFont;
        sansSerif = monoFont;
        serif = monoFont;
        emoji = monoFont;

        # Font sizes
        sizes = {
          desktop = 14;
          applications = 14;
          terminal = 16;
          popups = 16;
        };
      };
    };
  };
}
