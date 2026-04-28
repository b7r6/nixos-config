# Hypermodern Emacs - Sane Mutable Configuration
#
# Philosophy:
#   - Nix provides: emacs binary, packages, language servers, fonts
#   - User owns: ~/.emacs.d (init.el, custom.el, eln-cache, recentf, etc)
#   - init.el uses `use-package-always-ensure nil` since packages come from Nix
#
# With impermanence: add .emacs.d to persisted directories
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hyper-modern-nixos.emacs;

  mkHypermodernEmacs = import ./mk-hypermodern-emacs.nix;
in
{
  options.hyper-modern-nixos.emacs = {
    enable = lib.mkEnableOption "Hypermodern Emacs (Nix-managed packages, mutable config)";

    emacsPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.emacs30-pgtk;
      description = "Base Emacs derivation (e.g. emacs30-pgtk, emacs-git)";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = mkHypermodernEmacs {
        inherit pkgs;
        emacs = pkgs.emacs30-pgtk;
      };
      defaultText = "hypermodern-emacs (emacsWithPackages)";
      description = "The final Emacs package with all elisp packages bundled.";
    };

    languageServers.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install language servers for LSP support";
    };

    haskell.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Haskell language server (heavy ~1GB, disabled by default)";
    };

    rust.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Rust toolchain and language server";
    };

    lean4.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Lean 4 theorem prover (heavy ~500MB, disabled by default)";
    };

    fonts.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install programming fonts for Emacs";
    };

    # Seed config if ~/.emacs.d is empty/missing
    # Default false - manage ~/.emacs.d manually with symlinks for live editing
    seedConfig = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Seed ~/.emacs.d with hypermodern init.el (breaks live editing)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Disable stylix for emacs if present
    stylix.targets.emacs.enable = lib.mkDefault false;

    programs.emacs = {
      enable = true;
      package = cfg.package;
      # Don't use extraConfig - let user manage ~/.emacs.d/init.el
    };

    # Emacs config files managed by Nix (XDG path)
    xdg.configFile."emacs/early-init.el" = lib.mkIf cfg.seedConfig {
      source = ./early-init.el;
    };
    xdg.configFile."emacs/init.el" = lib.mkIf cfg.seedConfig {
      source = ./init.el;
    };

    # Symlink early-init/init into ~/.emacs.d so emacs finds them
    # (emacs only falls back to XDG_CONFIG_HOME if ~/.emacs.d doesn't exist)
    home.activation.emacsInitSymlinks = lib.mkIf cfg.seedConfig (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.emacs.d"
        target="$HOME/.emacs.d/init.el"
        link="$XDG_CONFIG_HOME/emacs/init.el"
        if [ -f "$link" ] && [ ! "$(readlink "$target" 2>/dev/null)" = "$link" ]; then
          ln -sf "$link" "$target"
        fi
        target="$HOME/.emacs.d/early-init.el"
        link="$XDG_CONFIG_HOME/emacs/early-init.el"
        if [ -f "$link" ] && [ ! "$(readlink "$target" 2>/dev/null)" = "$link" ]; then
          ln -sf "$link" "$target"
        fi
      ''
    );

    home.packages =
      with pkgs;
      lib.flatten [
        # Tree-sitter grammars
        emacs.pkgs.treesit-grammars.with-all-grammars

        # Core Language Servers (lightweight)
        (lib.optionals cfg.languageServers.enable [
          nixd
          pyright
          llvmPackages_19.clang-tools
          typescript-language-server
          vscode-langservers-extracted
          yaml-language-server
          bash-language-server
        ])

        # Haskell (heavy ~1GB)
        (lib.optionals cfg.haskell.enable [
          haskell-language-server
          haskellPackages.fourmolu
          haskellPackages.hlint
        ])

        # Rust toolchain
        (lib.optionals cfg.rust.enable [
          rustc
          cargo
          rust-analyzer
          rustfmt
          clippy
        ])

        # Lean 4 (heavy ~500MB)
        (lib.optional cfg.lean4.enable elan)

        # Formatters
        (lib.optionals cfg.languageServers.enable [
          nixpkgs-fmt
          ruff
          prettier
          shfmt
          buildifier
        ])

        # Linters
        (lib.optionals cfg.languageServers.enable [
          eslint
          yamllint
          shellcheck
        ])

        # Build tools
        cmake
        gnumake
        ninja

        # CLI tools Emacs expects
        ripgrep
        fd
        fzf
        git

        # Misc tools
        rclone
        pass
        gnupg

        # Fonts
        (lib.optionals cfg.fonts.enable [
          iosevka
          jetbrains-mono
          inter
          nerd-fonts.iosevka
          nerd-fonts.jetbrains-mono
        ])

        # Icons
        emacs-all-the-icons-fonts
      ];
  };
}
