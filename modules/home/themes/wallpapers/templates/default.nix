{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;

  mkWallpaper =
    args:
    let
      defaults = {
        width = 2560;
        height = 1440;
        dpi = 96;
        displayProfile = "generic";

        # Layout
        margin = 60;
        logoScale = 1.0;

        # Typography
        fontSizeTiny = 11;
        fontSizeSmall = 12;
        fontSizeMedium = 18;
        fontSizeHero = 36;
        fontWeightHero = 200;

        # Opacities
        codeOpacity = 0.7;
        storeOpacity = 0.6;
        statusOpacity = 0.5;
        interactiveOpacity = 0.4;
        accentOpacity = 0.15;

        # Content
        hostname = config.networking.hostName or "nixos";
        workdir = "~/hypermodern";
        command = "cat nix/modules/themes.nix";

        # Code content with proper templating
        codeContent = ''
          <tspan x="0" dy="18">{ <tspan fill="@BASE0E@">config</tspan>, <tspan fill="@BASE0E@">lib</tspan>, <tspan fill="@BASE0E@">flake</tspan>, ... }:</tspan>
          <tspan x="0" dy="18"><tspan fill="@BASE0A@" font-weight="600">let</tspan></tspan>
          <tspan x="0" dy="18">  <tspan fill="@BASE0A@">inherit</tspan> (flake) inputs;</tspan>
          <tspan x="0" dy="18">  cfg = config.hypermodern.themes;</tspan>
          <tspan x="0" dy="18"><tspan fill="@BASE0A@" font-weight="600">in</tspan> {</tspan>
          <tspan x="0" dy="18">  config = lib.mkIf cfg.enable {</tspan>
          <tspan x="0" dy="18">    stylix = {</tspan>
          <tspan x="0" dy="18">      base16Scheme = themes.''${cfg.theme}.''${cfg.variant};</tspan>
          <tspan x="0" dy="18">      fonts.monospace = {</tspan>
          <tspan x="0" dy="18">        package = berkeley-mono;</tspan>
          <tspan x="0" dy="18">        name = <tspan fill="@BASE0B@">"Berkeley Mono Medium"</tspan>;</tspan>
          <tspan x="0" dy="18">      };</tspan>
          <tspan x="0" dy="18">    };</tspan>
          <tspan x="0" dy="18">  };</tspan>
          <tspan x="0" dy="18">}</tspan>
        '';

        # Logo with customizable separators
        logoContent = ''
          <tspan fill="@BASE0A@" font-weight="700">//</tspan>
          <tspan fill="@BASE0E@" dx="24">hyper</tspan>
          <tspan fill="@BASE0A@" font-weight="700" dx="24">//</tspan>
          <tspan fill="@BASE0E@" dx="24">modern</tspan>
          <tspan fill="@BASE0A@" font-weight="700" dx="24">//</tspan>
          <tspan fill="@BASE0E@" dx="24">nixos</tspan>
        '';

        # Interactive command
        interactiveText = "$ nix run .#themes -- select";

        cursorElement = ''
          <rect x="360" y="-16" width="12" height="24" fill="@BASE0A@" opacity="0.9">
            <animate attributeName="opacity" values="0.9;0;0.9" dur="1s" repeatCount="indefinite"/>
          </rect>
        '';
      };

      params = defaults // args;

      positions = {
        storeX = params.width - params.margin;
        logoX = params.margin * 2;
        logoY = params.height - 240;
        statusX = params.width - params.margin;
        statusY = params.height - 160;
        interactiveX = params.width * 0.35;
        interactiveY = params.height * 0.42;
        accentX = 100;
        accentY = params.logoY - 100;
        accentWidth = 1400;
        accentHeight = 1;
      };

      allParams = params // positions;

    in
    pkgs.stdenv.mkDerivation {
      pname = "wallpaper-${params.theme.slug}-${toString params.width}x${toString params.height}";
      version = "1.0.1";

      src = ./templates;

      buildInputs = with pkgs; [
        inkscape
        imagemagick
        fontconfig
        liberation_ttf # fallback
      ];

      buildPhase = ''
        # Create a temporary font config
        export FONTCONFIG_FILE=${
          pkgs.makeFontsConf {
            fontDirectories = [ params.berkeleyMonoPath ];
          }
        }

        # Substitute all parameters
        cp hyper-modern.svg.template wallpaper.svg
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            key: value: "substituteInPlace wallpaper.svg --replace '@${lib.toUpper key}@' '${toString value}'"
          ) allParams
        )}

        # Also substitute theme colors
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            key: value: "substituteInPlace wallpaper.svg --replace '@${lib.toUpper key}@' '${value}'"
          ) params.theme.palette
        )}

        # Render with supersampling
        inkscape wallpaper.svg \
          --export-type=png \
          --export-filename=wallpaper-raw.png \
          --export-dpi=${toString (params.dpi * 2)}

        # Display-specific optimization
        ${import ./display-profiles.nix params.displayProfile}

        # Final output
        convert wallpaper-processed.png \
          -resize ${toString params.width}x${toString params.height} \
          -filter Lanczos \
          -unsharp 0x1 \
          wallpaper.png
      '';

      installPhase = ''
        mkdir -p $out
        cp wallpaper.png $out/
        cp wallpaper.svg $out/  # Keep the SVG for debugging
      '';
    };
in
{
  options.hypermodern.wallpaper = {
    enable = mkOption {
      type = types.bool;
      default = true;
    };

    package = mkOption {
      type = types.package;
      default = mkWallpaper {
        theme = config.hypermodern.themes.palette;
        berkeleyMonoPath = config.hypermodern.themes.fonts.monospace.package;
        displayProfile = config.hypermodern.display.profile or "generic";
        width = config.hypermodern.display.width or 2560;
        height = config.hypermodern.display.height or 1440;
        dpi = config.hypermodern.display.dpi or 96;
      };
    };
  };
}
