{
  config,
  lib,
  pkgs,
  ...
}:

let
  initEl      = builtins.readFile ./init.el;
  earlyInitEl = builtins.readFile ./early-init.el;

  # Helper: include package if it exists (keeps builds resilient).
  maybe = epkgs: name:
    if builtins.hasAttr name epkgs then [ (builtins.getAttr name epkgs) ] else [ ];

      mkLean4Mode = epkgs: epkgs.trivialBuild {
        pname = "lean4-mode";
        version = "2025-01-09";

        src = pkgs.fetchFromGitHub {
          owner = "leanprover";
          repo = "lean4-mode";
          rev = "1388f9d1429e38a39ab913c6daae55f6ce799479";
          hash = "sha256-6XFcyqSTx1CwNWqQvIc25cuQMwh3YXnbgr5cDiOCxBk=";
        };

        packageRequires = with epkgs; [ dash f flycheck lsp-mode magit-section s ];

        postInstall = ''
          cp -r $src/data $out/share/emacs/site-lisp/
        '';
      };

in
{
  # Disable stylix for Emacs - we have our own theme engine
  stylix.targets.emacs.enable = false;

  # Make sure Emacs sees early-init in both common locations.
  xdg.configFile."emacs/early-init.el".text = earlyInitEl;
  home.file.".emacs.d/early-init.el".text = earlyInitEl;

  programs.emacs = {
    enable = true;

    package = (pkgs.emacsPackagesFor pkgs.emacs30-pgtk).emacsWithPackages (epkgs:
      let
        core = with epkgs; [
          # UI / modeline
          doom-modeline
          nerd-icons
          dashboard

          # minibuffer / completion
          vertico
          orderless
          marginalia
          consult
          embark
          embark-consult
          general
          which-key
          popper
          shackle
          company
          yasnippet

          # icons
          all-the-icons
          all-the-icons-completion
          nerd-icons-completion

          # UI extras
          rainbow-mode
          dimmer
          ligature

          # git
          magit
          forge

          # terminals
          vterm
          eat

          # programming - LSP
          lsp-mode
          lsp-ui
          lsp-pyright
          lsp-haskell

          # programming - languages
          nix-mode
          haskell-mode
          rust-mode
          typescript-mode
          js2-mode
          web-mode
          yaml-mode
          markdown-mode
          json-mode
          dockerfile-mode
          csharp-mode
          fsharp-mode
          cuda-mode
          bazel  # just the mode, buildifier formatter, let projects provide bazel binary

          # lisp
          paredit
          paredit-everywhere

          # tree-sitter
          treesit-auto

          # navigation / search
          rg
          fzf
          avy
          ace-window
          projectile

          # editing
          undo-tree
          expand-region
          multiple-cursors
          format-all

          # tools
          direnv
          exec-path-from-shell
          helpful

          # AI
          gptel

          # misc
          transient
        ] ++ [ (mkLean4Mode epkgs) ];

        optional = (maybe epkgs "lean4-mode")
                ++ (maybe epkgs "atomic-chrome")
                ++ (maybe epkgs "elfeed")
                ++ (maybe epkgs "ement")
                ++ (maybe epkgs "telega")
                ++ (maybe epkgs "mastodon")
                ++ (maybe epkgs "pdf-tools")
                ++ (maybe epkgs "nov")
                ++ (maybe epkgs "clipetty");

      in
        core ++ optional
    );

    extraConfig = ''
      ;; ------------------------------------------------------------
      ;; init.el (inline themes, no external deps)
      ;; ------------------------------------------------------------
      ${initEl}
    '';
  };

  home.packages = with pkgs; [
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Tree-sitter grammars (all of them)
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    emacs.pkgs.treesit-grammars.with-all-grammars

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Language Servers (from hypermodern/language-registry)
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    nixd                                      # Nix
    haskell-language-server                   # Haskell
    rust-analyzer                             # Rust
    pyright                                   # Python
    clang-tools                               # C/C++/CUDA (clangd + clang-tidy)
    nodePackages.typescript-language-server   # TypeScript/JavaScript
    nodePackages.vscode-langservers-extracted # JSON, HTML, CSS, ESLint LSP
    nodePackages.yaml-language-server         # YAML
    nodePackages.bash-language-server         # Bash

    # Lean 4
    elan                          # Lean version manager (provides lean, lake)

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Formatters (from hypermodern/language-registry)
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    nixpkgs-fmt                   # Nix
    haskellPackages.fourmolu      # Haskell
    rustfmt                       # Rust
    ruff                          # Python (replaces black)
    nodePackages.prettier         # TypeScript/JavaScript/JSON/YAML
    shfmt                         # Bash
    buildifier                    # Bazel

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Linters (from hypermodern/language-registry)
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    haskellPackages.hlint         # Haskell
    clippy                        # Rust
    ruff                          # Python (same as formatter, does both)
    nodePackages.eslint           # TypeScript/JavaScript
    yamllint                      # YAML
    shellcheck                    # Bash

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Rust toolchain
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    rustc
    cargo

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Build tools
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    cmake
    gnumake
    ninja

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # CLI tools Emacs expects
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    ripgrep
    fd
    fzf
    git

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Misc tools
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    rclone
    pass
    gnupg

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Fonts
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    # berkeley-mono                 # if you have it packaged
    iosevka
    jetbrains-mono
    inter
    nerd-fonts.iosevka
    nerd-fonts.jetbrains-mono

    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    # Icons
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    emacs-all-the-icons-fonts
  ];
}
