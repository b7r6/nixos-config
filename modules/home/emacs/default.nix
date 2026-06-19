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

    # Seed config into ~/.emacs.d as REAL, EDITABLE files (not store symlinks).
    #
    # Rationale: XDG config that lives read-only in the nix store cannot be
    # live-edited, which is intolerable for an emacs config you iterate on.
    # When enabled, activation copies init.el/early-init.el/lib/themes into
    # ~/.emacs.d as writable files using last-writer-wins semantics:
    #   - file absent            -> copy the nix version
    #   - file == last-seeded    -> you haven't touched it; update to new version
    #   - file != last-seeded    -> you edited it; LEAVE IT ALONE (back up nix
    #                               version alongside as <file>.nix-new)
    # A per-file marker under ~/.emacs.d/.hypermodern-seed/ records the hash of
    # what we last wrote, so we can tell "unchanged" from "user-edited".
    seedConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Seed ~/.emacs.d with editable copies of the hypermodern config (LWW, preserves your edits)";
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

    # Seed ~/.emacs.d with EDITABLE copies (see seedConfig option for rationale
    # and the last-writer-wins semantics). We copy out of this store path; emacs
    # then loads ~/.emacs.d/init.el normally (it only falls back to XDG when
    # ~/.emacs.d is absent, which it won't be once seeded).
    home.activation.emacsSeedConfig = lib.mkIf cfg.seedConfig (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        emacs_dir="$HOME/.emacs.d"
        marker_dir="$emacs_dir/.hypermodern-seed"
        run mkdir -p "$emacs_dir" "$marker_dir"

        # seed_file <store-source-path> <dest-relative-under-.emacs.d>
        seed_file() {
          src="$1"
          dest="$emacs_dir/$2"
          marker="$marker_dir/$(echo "$2" | tr '/' '_').sha256"
          [ -f "$src" ] || return 0
          run mkdir -p "$(dirname "$dest")"

          src_hash="$(sha256sum "$src" | cut -d' ' -f1)"

          # A symlink here is leftover from an older store-symlink-based config
          # (and may be DANGLING, which makes `-e` false and `cp` refuse to write
          # "through dangling symlink"). We own editable real files now, so drop
          # any symlink unconditionally and reseed. -h catches broken links too.
          if [ -h "$dest" ]; then
            run rm -f "$dest"
          fi

          if [ ! -e "$dest" ]; then
            # absent: take the nix version
            run cp -f "$src" "$dest"
            run chmod u+w "$dest"
            echo "$src_hash" > "$marker"
          else
            dest_hash="$(sha256sum "$dest" | cut -d' ' -f1)"
            last_hash="$(cat "$marker" 2>/dev/null || echo none)"
            if [ "$dest_hash" = "$src_hash" ]; then
              : # already up to date
            elif [ "$dest_hash" = "$last_hash" ]; then
              # unchanged since we last seeded -> safe to update
              run cp -f "$src" "$dest"
              run chmod u+w "$dest"
              echo "$src_hash" > "$marker"
            else
              # user-edited: never clobber. Drop the new nix version alongside.
              run cp -f "$src" "$dest.nix-new"
              run chmod u+w "$dest.nix-new"
              warnEcho "[emacs] $2 has local edits; new version written to $2.nix-new"
            fi
          fi
        }

        # Only the files emacs actually loads. (lib/*.el and themes/*.el are
        # not referenced by the active init.el; don't seed dead files.)
        seed_file ${./init.el}       init.el
        seed_file ${./early-init.el} early-init.el
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
