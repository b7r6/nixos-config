# mk-hypermodern-emacs.nix
#
# Build emacs with all packages pre-installed via Nix.
# init.el lives in ~/.emacs.d and uses `use-package-always-ensure nil`.
#
{
  pkgs,
  emacs ? pkgs.emacs30-pgtk,
  extraPackages ? (_: [ ]),
}:

let
  lib = pkgs.lib;

  # Helper: include package if it exists (keeps builds resilient).
  maybe = epkgs: name: if lib.hasAttr name epkgs then [ epkgs.${name} ] else [ ];

  mkLean4Mode =
    epkgs:
    epkgs.trivialBuild {
      pname = "lean4-mode";
      version = "2025-01-09";

      src = pkgs.fetchFromGitHub {
        owner = "leanprover";
        repo = "lean4-mode";
        rev = "1388f9d1429e38a39ab913c6daae55f6ce799479";
        hash = "sha256-6XFcyqSTx1CwNWqQvIc25cuQMwh3YXnbgr5cDiOCxBk=";
      };

      packageRequires = with epkgs; [
        dash
        f
        flycheck
        lsp-mode
        magit-section
        s
      ];

      postInstall = ''
        cp -r $src/data $out/share/emacs/site-lisp/
      '';
    };

  emacsPkgs = pkgs.emacsPackagesFor emacs;
in
emacsPkgs.emacsWithPackages (
  epkgs:
  let
    core =
      with epkgs;
      [
        # Core glue (Nix-managed; init.el must not install packages)
        use-package

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
        prescient
        vertico-prescient
        company-prescient
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
        dhall-mode
        json-mode
        dockerfile-mode
        csharp-mode
        fsharp-mode
        cuda-mode
        bazel # mode only; let projects provide bazel binary

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

        # secrets / password management
        password-store
        password-store-otp
        pass

        # misc
        transient
      ]
      ++ [ (mkLean4Mode epkgs) ];

    optional =
      (maybe epkgs "atomic-chrome")
      ++ (maybe epkgs "elfeed")
      ++ (maybe epkgs "ement")
      ++ (maybe epkgs "telega")
      ++ (maybe epkgs "mastodon")
      ++ (maybe epkgs "pdf-tools")
      ++ (maybe epkgs "nov")
      ++ (maybe epkgs "clipetty");

  in
  core ++ optional ++ (extraPackages epkgs)
)
