{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types mkIf;
  cfg = config.hypermodern;

  mkWallpaper =
    args:
    let
      baseWidth = 2560;

      defaults = {
        width = 2560;
        height = 1440;
        dpi = 96;
        display-profile = "generic";

        theme =
          cfg.wallpaper.customize.theme or {
            slug = "default";
            inherit (cfg.themes) palette;
          };

        berkeley-mono-path = "${pkgs.callPackage ../fonts/berkeley-mono { }}/share/fonts/opentype";

        # Base sizes
        base-font-size-tiny = 20;
        base-font-size-small = 24;
        base-font-size-medium = 36;
        base-font-size-hero = 48;
        font-weight-hero = 500;

        # Opacities
        code-opacity = 0.85;
        store-opacity = 0.85;
        status-opacity = 0.85;
        interactive-opacity = 0.6;
        accent-opacity = 0.35;

        # Dynamic content
        hostname = config.networking.hostName or "nixos";
      };

      params = defaults // args;

      # Calculate scale factor AFTER merging args
      scale-factor = params.width / baseWidth;

      # Calculate all scaled values that the template expects
      scaledParams = {
        # Scaled fonts
        font-size-tiny = builtins.floor (params.base-font-size-tiny * scale-factor);
        font-size-small = builtins.floor (params.base-font-size-small * scale-factor);
        font-size-medium = builtins.floor (params.base-font-size-medium * scale-factor);
        font-size-hero = builtins.floor (params.base-font-size-hero * scale-factor);

        theme-name = params.theme.slug;

        # Scaled margin
        margin = builtins.floor (60 * scale-factor);

        # Store visualization position (top right)
        store-x = params.width - builtins.floor (60 * scale-factor);

        # Main hero text position (lower left)
        logo-x = builtins.floor (120 * scale-factor);
        logo-y = builtins.floor (params.height * 0.95);

        # Status output position (bottom right)
        status-x = params.width - builtins.floor (60 * scale-factor);
        status-y = params.height - builtins.floor (180 * scale-factor);

        # Interactive command position (center)
        interactive-x = builtins.floor (params.width * 0.35);
        interactive-y = builtins.floor (params.height * 0.45);

        # Accent line position
        accent-x = builtins.floor (100 * scale-factor);
        accent-y = builtins.floor (params.height * 0.75);
        accent-width = builtins.floor (1400 * scale-factor);
        accent-height = builtins.floor (2 * scale-factor);

        # Cursor position (after the command text)
        cursor-x = builtins.floor (590 * scale-factor);
      };

      allParams = params // scaledParams;

    in
    pkgs.stdenv.mkDerivation {
      pname = "hyper-modern-wallpaper-${allParams.theme.slug}";
      version = "1.0.0";

      src = ./templates;

      nativeBuildInputs = with pkgs; [
        librsvg
        imagemagick
        fontconfig
      ];

      buildPhase = ''
        export HOME=$TMPDIR
        export FC_CACHE_DIR=$TMPDIR/fontconfig
        export FONTCONFIG_PATH=${pkgs.fontconfig.out}/etc/fonts
        export FONTCONFIG_FILE=${
          pkgs.makeFontsConf {
            fontDirectories = [ allParams.berkeley-mono-path ];
          }
        }

        mkdir -p $FC_CACHE_DIR

        cp hyper-modern.svg.template wallpaper.svg

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            key: value:
            if key == "theme" || lib.hasPrefix "base-" key then
              ""
            else
              "substituteInPlace wallpaper.svg --replace-warn '@${lib.toUpper key}@' '${toString value}'"
          ) allParams
        )}

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            key: value: "substituteInPlace wallpaper.svg --replace-warn '@${lib.toUpper key}@' '${value}'"
          ) allParams.theme.palette
        )}

        rsvg-convert \
          --width=${toString (allParams.width * 2)} \
          --height=${toString (allParams.height * 2)} \
          --output=wallpaper-raw.png \
          wallpaper.svg

        ${import ./display-profiles.nix allParams.display-profile}

        magick wallpaper-processed.png \
          -resize ${toString allParams.width}x${toString allParams.height} \
          -filter Lanczos \
          -unsharp 0x1 \
          wallpaper.png
      '';

      installPhase = ''
        mkdir -p $out
        cp wallpaper.png $out/
        cp wallpaper.svg $out/
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
      default = mkWallpaper { };
    };

    customize = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Override wallpaper generation parameters";
      example = {
        width = 3840;
        height = 2400;
        display-profile = "samsung-e6";
      };
    };
  };

  config = mkIf cfg.wallpaper.enable {
    hypermodern.wallpaper.package = mkWallpaper cfg.wallpaper.customize;
  };
}
