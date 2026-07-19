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

    # emacs-unstable-pgtk is the Emacs 31 PRETEST (31.0.90, tracks the emacs-31
    # release branch) from the emacs-overlay. nixpkgs and the overlay's plain
    # `emacs-pgtk` are both still 30.2; `emacs-git-pgtk` is post-31 master (more
    # churn). 31.0.90 is the sweet spot: real 31, branch-frozen. Override to
    # pkgs.emacs30-pgtk to drop back to nixpkgs stable if a build regresses.
    emacsPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.emacs-unstable-pgtk;
      description = "Base Emacs derivation (e.g. emacs-unstable-pgtk [31 pretest], emacs30-pgtk, emacs-git-pgtk)";
    };

    package = lib.mkOption {
      type = lib.types.package;

      default = mkHypermodernEmacs {
        inherit pkgs;
        emacs = cfg.emacsPackage;
      };

      defaultText = "hypermodern-emacs (emacsWithPackages)";
      description = "The final Emacs package with all elisp packages bundled.";
    };

    languageServers.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install language servers for LSP support";
    };

    nixlang.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable `nixlang` development tools";
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

    dhall.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Dhall tooling";
    };

    purescript.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable PureScript toolchain (purs, spago, language server, purs-tidy)";
    };

    fonts.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install programming fonts for Emacs";
    };

    # Link init.el/early-init.el from the repo checkout (dotfiles/emacs/) into
    # ~/.emacs.d as OUT-OF-STORE symlinks. The repo is home; editing either
    # side is the same file and lands in `git diff` — no rebuild, no seeding,
    # no drift. State (eln-cache, recentf, custom.el…) stays as real files in
    # ~/.emacs.d beside the links. This supersedes the old copy-and-hash
    # seeding machinery (LWW); migration from it is automatic when the live
    # files match the repo, and refuses to run when they don't.
    repoConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Symlink ~/.emacs.d/{init,early-init}.el into the dotfiles checkout (repo-homed config)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Disable stylix for emacs if present
    stylix.targets.emacs.enable = lib.mkDefault false;

    programs.emacs = {
      enable = true;
      inherit (cfg) package;
      # Don't use extraConfig - let user manage ~/.emacs.d/init.el
    };

    # Migration from the copy-and-hash seed era: the real files at
    # ~/.emacs.d/{init,early-init}.el must yield to symlinks, but ONLY when
    # they match the repo (or the last-seeded hash) — a diverged file means
    # un-committed local edits, and we abort the switch rather than eat them.
    # Runs before home-manager's own link-target check so the symlink lands
    # cleanly.
    home.activation.emacsRepoConfigMigrate = lib.mkIf cfg.repoConfig (
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        _repo="${config.hyper-modern-nixos.dotfiles.path}/emacs"
        _dir="$HOME/.emacs.d"
        for f in init.el early-init.el hypermodern-palette.el; do
          dest="$_dir/$f"
          # Real file (not symlink) in the way of the managed link?
          if [ -f "$dest" ] && [ ! -h "$dest" ]; then
            if [ -f "$_repo/$f" ] && cmp -s "$dest" "$_repo/$f"; then
              run rm -f "$dest"   # identical to repo: safe to yield
            else
              errorEcho "[emacs] $dest differs from $_repo/$f — commit or copy your edits into the repo, then re-switch (repo-homed config refuses to clobber)"
              exit 1
            fi
          fi
        done
        # The seed markers are dead machinery now.
        run rm -rf "$_dir/.hypermodern-seed"
      ''
    );

    # The links themselves: ~/.emacs.d/{init,early-init,hypermodern-palette}.el
    # → the working tree.
    home.file = lib.mkIf cfg.repoConfig {
      ".emacs.d/init.el".source = config.lib.file.mkOutOfStoreSymlink "${config.hyper-modern-nixos.dotfiles.path}/emacs/init.el";
      ".emacs.d/early-init.el".source = config.lib.file.mkOutOfStoreSymlink "${config.hyper-modern-nixos.dotfiles.path}/emacs/early-init.el";
      ".emacs.d/hypermodern-palette.el".source = config.lib.file.mkOutOfStoreSymlink "${config.hyper-modern-nixos.dotfiles.path}/emacs/hypermodern-palette.el";
    };

    # Emacs daemon: the socket wintermute's emacsclient adapter lands on
    # ((ono-sendai-set-hero …) today, (ono-sendai-sync) once the adapter is
    # bumped). Standalone `emacs` sessions are unaffected.
    services.emacs = {
      enable = true;
      inherit (cfg) package;
      client.enable = true;
    };

    home.packages =
      with pkgs;
      lib.flatten [
        # Tree-sitter grammars
        emacs.pkgs.treesit-grammars.with-all-grammars

        # Core Language Servers (lightweight)
        (lib.optionals cfg.languageServers.enable [
          nixd
          pyright
          # keep in lockstep with modules/home/dev (llvmPackages_22) — two
          # different clang-tools in one profile collide on bin/clang-*.
          llvmPackages_22.clang-tools
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

        (lib.optionals cfg.nixlang.enable [
          deadnix
          nil
          nixd
          nixpkgs-fmt
          statix
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

        # Dhall
        (lib.optional cfg.dhall.enable [
          dhall
          dhall-lsp-server
          dhall-nix
          dhall-nixpkgs
          dhall-bash
        ])

        # PureScript
        # purs/spago come from nixpkgs; the language server and purs-tidy are
        # npm-distributed and not in nixpkgs, so we package them locally.
        (lib.optionals cfg.purescript.enable [
          purescript
          spago
          (pkgs.callPackage ./pkgs/purescript-language-server { })
          (pkgs.callPackage ./pkgs/purs-tidy { })
        ])

        # Formatters
        # nixfmt (RFC-style) is the formatter treefmt uses
        # (modules/flake/fmt.nix). Emacs' format-all "Nix" entry shells out to
        # the `nixfmt` binary, so on-save formatting matches treefmt exactly
        # instead of diverging via nixpkgs-fmt.
        (lib.optionals cfg.languageServers.enable [
          nixfmt
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
