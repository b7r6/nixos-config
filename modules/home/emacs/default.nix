{
  config,
  lib,
  pkgs,
  stylix,
  ...
}:
let
  initialInitEl = builtins.readFile ./init.el;

  localLibs = pkgs.symlinkJoin {
    name = "emacs-local-libs";
    paths = lib.mapAttrsToList (
      name: _value:
      pkgs.writeTextFile {
        inherit name;
        text = builtins.readFile (./lib + "/${name}");
        destination = "/share/emacs/site-lisp/${name}";
      }
    ) (lib.filterAttrs (n: _v: lib.hasSuffix ".el" n) (builtins.readDir ./lib));
  };
in
{
  stylix.targets.emacs.enable = true;

  programs.emacs = {
    enable = true;

    package = (pkgs.emacsPackagesFor pkgs.emacs30-pgtk).emacsWithPackages (
      epkgs: with epkgs; [
        (epkgs.trivialBuild (
          with config.lib.stylix.colors.withHashtag;
          {
            pname = "base16-stylix-theme";
            version = "0.1.0";

            src = pkgs.writeText "base16-stylix-theme.el" ''
              (require 'base16-theme)
              (defvar base16-stylix-theme-colors
                '(:base00 "${base00}"
                  :base01 "${base01}"
                  :base02 "${base02}"
                  :base03 "${base03}"
                  :base04 "${base04}"
                  :base05 "${base05}"
                  :base06 "${base06}"
                  :base07 "${base07}"
                  :base08 "${base08}"
                  :base09 "${base09}"
                  :base0A "${base0A}"
                  :base0B "${base0B}"
                  :base0C "${base0C}"
                  :base0D "${base0D}"
                  :base0E "${base0E}"
                  :base0F "${base0F}")
                "All colors for Base16 stylix are defined here.")
              ;; Define the theme
              (deftheme base16-stylix)
              ;; Add all the faces to the theme
              (base16-theme-define 'base16-stylix base16-stylix-theme-colors)
              ;; Mark the theme as provided
              (provide-theme 'base16-stylix)
              ;; Add path to theme to theme-path
              (add-to-list 'custom-theme-load-path
                  (file-name-directory
                      (file-truename load-file-name)))
              (provide 'base16-stylix-theme)
            '';

            packageRequires = [ epkgs.base16-theme ];
          }
        ))

        all-the-icons
        all-the-icons-completion
        apheleia
        autothemer
        base16-theme
        bazel
        bind-key
        breadcrumb
        clang-format
        clipetty
        cmake-mode
        company
        company-ghci
        consult
        consult-eglot
        corfu
        csv-mode
        cuda-mode
        dashboard
        direnv
        dirvish
        dockerfile-mode
        doom-modeline
        eglot
        eldoc-box
        expand-region
        f
        flycheck
        flycheck
        flycheck-haskell
        flymake-diagnostic-at-point
        fontify-face
        format-all
        fsharp-mode
        fzf
        general
        gptel
        haskell-mode
        hcl-mode
        ht
        iter2
        json-mode
        just-mode
        language-id
        llama
        lsp-haskell
        lsp-mode
        lsp-python-ms
        lsp-pyright
        lsp-treemacs
        lsp-ui
        lua-mode
        lv
        magit
        marginalia
        markdown-mode
        multiple-cursors
        mustache-mode
        nerd-icons
        nerd-icons-completion
        nix-mode
        nix-ts-mode
        nixpkgs-fmt
        nvm
        orderless
        org-bullets
        paredit
        paredit-everywhere
        popper
        posframe
        prettier
        prisma-mode
        projectile
        protobuf-mode
        py-isort
        python
        rainbow-delimiters
        rainbow-mode
        reformatter
        rg
        ruff-format
        s
        shackle
        shrink-path
        sideline
        sideline-flymake
        sideline-lsp
        spinner
        swift-mode
        terraform-mode
        treesit-auto
        treesit-grammars.with-all-grammars
        typescript-mode
        vertico
        vterm
        wgrep
        which-key
        with-editor
        yaml-mode
        yapfify
        yasnippet
        zig-mode
      ]
    );

    extraConfig = ''
      ${initialInitEl}

      ;; Add local libs directory to load-path
      (add-to-list 'load-path "${localLibs}/share/emacs/site-lisp")

      ;; Load all .el files from local libs
      (dolist (file (directory-files "${localLibs}/share/emacs/site-lisp" t "\\.el$"))
        (load file))
    '';
  };

  home.packages = [
    pkgs.basedpyright
    pkgs.csharp-ls
    pkgs.emacs-all-the-icons-fonts
    pkgs.emacs-lsp-booster
    localLibs
  ];
}
