{
  flake,
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (flake) inputs;

  # TODO[b7r6]: Replace this with a proper fetchFromGitHub or similar approach
  # This is a temporary solution until we have a proper way to handle Berkeley Mono
  berkeley-mono = pkgs.stdenv.mkDerivation {
    name = "berkeley-mono-font";
    src = ./.;

    dontUnpack = true;
    installPhase = ''
      mkdir -p $out/share/fonts/opentype
      cp ${./berkeley-mono-semi-bold.otf} $out/share/fonts/opentype/
    '';
  };

  ono-sendai-blue = {
    slug = "ono-sendai-blue";
    name = "Ono-Sendai Hyper Modern Blue";
    author = "b7r6";
    variant = "dark";

    palette = {
      base00 = "#090b0e";
      base01 = "#13161a";
      base02 = "#1a1f24";
      base03 = "#23292f";
      base04 = "#23292f";
      base05 = "#d8e0e7";
      base06 = "#596775";
      base07 = "#ddf4ff";
      base08 = "#b6e3ff";
      base09 = "#80ccff";
      base0A = "#54aeff";
      base0B = "#218bff";
      base0C = "#0969da";
      base0D = "#54aeff";
      base0E = "#80ccff";
      base0F = "#218bff";
    };
  };

  ono-sendai-vibrant = {
    slug = "ono-sendai-vibrant";
    name = "Ono-Sendai Hyper Modern Vibrant";
    author = "b7r6";
    variant = "dark";

    palette = {
      base00 = "#0F1216";
      base01 = "#171C22";
      base02 = "#21262d";
      base03 = "#30363d";
      base04 = "#8b949e";
      base05 = "#b1bac4";
      base06 = "#c9d1d9";
      base07 = "#f0f6fc";
      base08 = "#96cffe";
      base09 = "#96cffe";
      base0A = "#f49b4f";
      base0B = "#539bf5";
      base0C = "#d5b7f4";
      base0D = "#96cffe";
      base0E = "#96cffe";
      base0F = "#d5b7f4";
    };
  };

  github-dark-dimmed = {
    slug = "github-dark-dimmed";
    name = "GitHub Dark Dimmed";
    author = "GitHub";
    variant = "dark";

    palette = {
      base00 = "#22272e"; # bg
      base01 = "#2d333b"; # lighter bg
      base02 = "#444c56"; # selection bg
      base03 = "#768390"; # comments
      base04 = "#adbac7"; # dark fg
      base05 = "#cdd9e5"; # fg
      base06 = "#d0d7de"; # light fg
      base07 = "#f6f8fa"; # light bg
      base08 = "#f47067"; # red
      base09 = "#e0823d"; # orange
      base0A = "#c69026"; # yellow
      base0B = "#57ab5a"; # green
      base0C = "#539bf5"; # cyan
      base0D = "#539bf5"; # blue
      base0E = "#c297ff"; # purple
      base0F = "#c69026"; # brown
    };
  };

  berkeleyMonoExists = builtins.pathExists ./berkeley-mono-semi-bold.otf;

  monoFont =
    if berkeleyMonoExists then
      {
        package = berkeley-mono;
        name = "Berkeley Mono";
      }
    else
      {
        package = pkgs.jetbrains-mono;
        name = "JetBrains Mono";
      };
in
{
  imports = [ inputs.stylix.homeManagerModules.stylix ];

  # Define palette as a computed option
  options = {
    themes.palette = lib.mkOption {
      type = lib.types.attrs;
      description = "The base16 theme palette with hashtags for use in configurations";
      internal = true;
      readOnly = true;
      default = { };
      apply = _: config.lib.stylix.colors.withHashtag;
    };
  };

  config = {
    stylix = {
      enable = true;
      autoEnable = true;

      image = ./nix-glow-black.png;

      base16Scheme = ono-sendai-blue;

      fonts = {
        monospace = monoFont;
        sansSerif = monoFont;
        serif = monoFont;
        emoji = monoFont;

        # Font sizes
        sizes = {
          desktop = 18;
          applications = 12;
          terminal = 16;
          popups = 16;
        };
      };
    };
  };
}
