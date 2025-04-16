{
  config,
  lib,
  pkgs,
  stylix,
  ...
}:
let
  initialInitEl = builtins.readFile ./init.el;
in
{
  # stylix.targets.emacs.enable = true;

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
        clang-format
        clipetty
        cmake-mode
        company
        consult
        corfu
        csv-mode
        dashboard
        direnv
        dirvish
        dockerfile-mode
        doom-modeline
        eglot
        expand-region
        f
        flycheck
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
        lsp-mode
        lsp-python-ms
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
        shrink-path
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

    extraPackages = epkgs: [ ];
    extraConfig = initialInitEl;
  };

  home.packages = [
    pkgs.emacs-all-the-icons-fonts
    pkgs.emacs-lsp-booster
  ];
}
