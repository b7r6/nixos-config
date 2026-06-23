# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                       // hyper-modern-nixos // flake // themes
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Flake-level theme configuration module (flake-parts)
#
# This module is the computational core of the Ono-Sendai theme system:
#   - Pure Nix HSL color math (lib/ono-sendai.nix)
#   - Lean4 theme generator for editor plugins (packages/ono-sendai-generator)
#   - SVG wallpaper generation
#
# The resolved theme can be consumed by both NixOS and home-manager modules.
#
{ config, lib, ... }:

let
  inherit (lib) mkOption mkEnableOption types;

  # Import the pure-Nix color math library (no config dependency)
  color-lib = import ./lib.nix { inherit lib; };

  # ── Theme package builders (parameterized, no config dependency) ─────────────

  # Build an Emacs theme package using the Lean generator
  mkEmacsTheme =
    pkgs:
    {
      level,
      hero-hue,
      axis-hue,
    }:
    let
      generator = pkgs.callPackage ./packages/ono-sendai-generator { };
    in
    pkgs.runCommand "ono-sendai-emacs-theme" { } ''
      mkdir -p $out/share/emacs/site-lisp
      ${generator}/bin/ono-sendai-gen emacs ${level} ${toString hero-hue} ${toString axis-hue} \
        > $out/share/emacs/site-lisp/ono-sendai-theme.el
    '';

  # Build a Neovim theme package using the Lean generator
  mkNeovimTheme =
    pkgs: _:
    let
      generator = pkgs.callPackage ./packages/ono-sendai-generator { };
    in
    pkgs.runCommand "ono-sendai-nvim-theme" { } ''
      mkdir -p $out/lua/ono-sendai
      mkdir -p $out/plugin

      ${generator}/bin/ono-sendai-gen nvim-palette > $out/lua/ono-sendai/palette.lua
      ${generator}/bin/ono-sendai-gen nvim-init > $out/lua/ono-sendai/init.lua
      ${generator}/bin/ono-sendai-gen nvim-plugin > $out/plugin/ono-sendai.lua
    '';

  # Build an SVG wallpaper
  mkWallpaper =
    pkgs:
    {
      palette,
      width ? 3840,
      height ? 2160,
    }:
    pkgs.runCommand "ono-sendai-wallpaper" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
      mkdir -p $out

      # Generate a minimal gradient wallpaper with theme colors
      magick -size ${toString width}x${toString height} \
        xc:"${palette.base00}" \
        -fill "${palette.base01}" \
        -draw "rectangle 0,${toString (height - 120)} ${toString width},${toString height}" \
        -fill "${palette.base0D}" \
        -draw "rectangle 0,${toString (height - 4)} ${toString width},${toString height}" \
        $out/wallpaper.png

      # Also generate an SVG version for reference
      cat > $out/wallpaper.svg << 'EOF'
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${toString width} ${toString height}">
        <rect fill="${palette.base00}" width="100%" height="100%"/>
        <rect fill="${palette.base01}" y="${toString (height - 120)}" width="100%" height="120"/>
        <rect fill="${palette.base0D}" y="${toString (height - 4)}" width="100%" height="4"/>
      </svg>
      EOF
    '';

in
{
  options.flake.themes = {
    enable = mkEnableOption "Ono-Sendai color theme system" // {
      default = true;
    };

    # ── Core theme parameters ────────────────────────────────────────────────────

    level = mkOption {
      type = types.enum [
        "void"
        "deep"
        "night"
        "carbon"
        "github"
      ];
      default = "night";
      description = ''
        Black level for the theme:
          void   - L=0%  (true black, kills thin fonts)
          deep   - L=4%  (hand-tuned dark)
          night  - L=8%  (OLED safe threshold)
          carbon - L=11% (recommended default)
          github - L=16% (matches GitHub dark mode)
      '';
    };

    hero-hue = mkOption {
      type = types.ints.between 0 359;
      default = 211;
      description = ''
        Hero accent hue (0-359). Controls base0A-0F colors:
        classes, strings, support, functions, keywords, deprecated.
      '';
    };

    axis-hue = mkOption {
      type = types.ints.between 0 359;
      default = 201;
      description = ''
        Axis accent hue (0-359). Controls base08-09 colors:
        variables and integers (the "cool shift").
      '';
    };

    # ── Editor theme generation ──────────────────────────────────────────────────

    editors = mkOption {
      type = types.submodule {
        options = {
          emacs = mkEnableOption "Emacs theme generation via Lean4";
          neovim = mkEnableOption "Neovim theme generation via Lean4";
          vscode = mkEnableOption "VSCode theme generation via Lean4";
        };
      };
      default = { };
      description = "Editor theme generation options (uses Lean4 generator)";
    };

    # ── Wallpaper options ────────────────────────────────────────────────────────

    wallpaper = mkOption {
      type = types.submodule {
        options = {
          enable = mkEnableOption "Generate themed wallpaper";
          width = mkOption {
            type = types.int;
            default = 3840;
            description = "Wallpaper width in pixels";
          };
          height = mkOption {
            type = types.int;
            default = 2160;
            description = "Wallpaper height in pixels";
          };
        };
      };
      default = { };
      description = "Wallpaper generation options";
    };
  };

  # NOTE: We don't use mkIf here because flake.lib should always be available
  # The perSystem packages are conditionally built based on options
  config = {
    # Expose the theme lib via flake outputs for external consumers
    # This is always available, regardless of enable status
    flake.lib.themes = {
      inherit
        color-lib
        mkEmacsTheme
        mkNeovimTheme
        mkWallpaper
        ;

      # Helpers for generating themes with custom parameters
      mkTheme = color-lib.mk-theme;
      mkPalette = color-lib.make-palette;

      # Convenience: get resolved theme for given params
      resolve =
        {
          level,
          hero-hue ? 211,
          axis-hue ? 201,
        }:
        color-lib.mk-theme { inherit level hero-hue axis-hue; };
    };

    # Per-system packages for editor themes
    # These use the flake.themes config options
    perSystem =
      { pkgs, ... }:
      let
        cfg = config.flake.themes;
        resolvedTheme = color-lib.mk-theme {
          inherit (cfg) level;
          inherit (cfg) hero-hue;
          inherit (cfg) axis-hue;
        };
      in
      {
        packages = lib.mkMerge [
          # Always expose the palette as JSON for debugging/external tools
          (lib.mkIf cfg.enable {
            ono-sendai-palette = pkgs.writeTextFile {
              name = "ono-sendai-palette";
              text = builtins.toJSON resolvedTheme;
              destination = "/share/themes/ono-sendai.json";
            };
          })

          # ono-sendai-generator lives at ./packages/ono-sendai-generator/

          # Emacs theme package (if enabled)
          (lib.mkIf (cfg.enable && cfg.editors.emacs) {
            ono-sendai-emacs = mkEmacsTheme pkgs { inherit (cfg) level hero-hue axis-hue; };
          })

          # Neovim theme package (if enabled)
          (lib.mkIf (cfg.enable && cfg.editors.neovim) {
            ono-sendai-neovim = mkNeovimTheme pkgs { inherit (cfg) level hero-hue axis-hue; };
          })

          # Wallpaper package (if enabled)
          (lib.mkIf (cfg.enable && cfg.wallpaper.enable) {
            ono-sendai-wallpaper = mkWallpaper pkgs {
              inherit (resolvedTheme) palette;
              inherit (cfg.wallpaper) width height;
            };
          })
        ];
      };
  };
}
