# mk-hypermodern-emacs.nix
#
# Build emacs with all packages pre-installed via Nix.
# init.el lives in ~/.emacs.d and uses `use-package-always-ensure nil`.
#
{
  pkgs,
  emacs ? pkgs.emacs-unstable-pgtk, # emacs-overlay 31 pretest; pass emacs30-pgtk for stable

  extraPackages ? (_: [ ]),
}:

let
  inherit (pkgs) lib;

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
        popper # placement lives in display-buffer-alist (see init.el popup table)
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
        #
        # ghostel is the primary terminal: a libghostty-vt-backed emulator that
        # is faster and more correct than vterm (true color, kitty keyboard +
        # graphics, hyperlinks, shell integration out of the box). The nixpkgs
        # build VENDORS the prebuilt native module (ghostel-module.so) inside
        # the read-only store path, and ghostel-module-directory defaults to nil
        # ("read the module from the package directory"), so it loads the
        # vendored .so in place and NEVER hits its first-use auto-download path.
        # init.el additionally pins ghostel-module-auto-install nil as a
        # belt-and-suspenders guard. vterm/eat stay installed as fallbacks.
        ghostel
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
        purescript-mode
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
        move-dup
        ws-butler
        format-all
        wgrep
        symbol-overlay

        # git decoration / dired
        diff-hl
        hl-todo
        magit-todos
        diredfl

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
