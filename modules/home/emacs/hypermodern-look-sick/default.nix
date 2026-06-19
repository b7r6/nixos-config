{
  config,
  lib,
  pkgs,
  stylix,
  ...
}:

let
  initEl = builtins.readFile ./init.el;
  earlyInitEl = builtins.readFile ./early-init.el;

  # Ship ./lib/*.el into site-lisp and load them at startup.
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

  # Helper: include package if it exists (keeps builds resilient).
  maybe = epkgs: name: if builtins.hasAttr name epkgs then [ (builtins.getAttr name epkgs) ] else [ ];

  # ------------------------------------------------------------
  # Ono-Sendai theme universe (build Emacs themes from Nix palettes)
  # ------------------------------------------------------------
  ono = import ./ono-sendai-blue.nix;
  onoSchemes = lib.filterAttrs (_name: v: (v ? palette) && (v ? slug) && (v ? name)) ono;

  mkBase16Theme =
    epkgs: scheme:
    let
      themeSym = "base16-${scheme.slug}";
      colorsVar = "${themeSym}-theme-colors";
      p = scheme.palette;
      # helper for palette keys
      c = k: builtins.getAttr k p;
    in
    epkgs.trivialBuild {
      pname = "${themeSym}-theme";
      version = "0.1.0";
      src = pkgs.writeText "${themeSym}-theme.el" ''
        (require 'base16-theme)

        (defvar ${colorsVar}
          '(:base00 "${c "base00"}"
            :base01 "${c "base01"}"
            :base02 "${c "base02"}"
            :base03 "${c "base03"}"
            :base04 "${c "base04"}"
            :base05 "${c "base05"}"
            :base06 "${c "base06"}"
            :base07 "${c "base07"}"
            :base08 "${c "base08"}"
            :base09 "${c "base09"}"
            :base0A "${c "base0A"}"
            :base0B "${c "base0B"}"
            :base0C "${c "base0C"}"
            :base0D "${c "base0D"}"
            :base0E "${c "base0E"}"
            :base0F "${c "base0F"}")
          "Base16 palette for ${themeSym}.")

        (deftheme ${themeSym})
        (base16-theme-define '${themeSym} ${colorsVar})
        (provide-theme '${themeSym})
        (provide '${themeSym}-theme)

        (add-to-list 'custom-theme-load-path
                     (file-name-directory (file-truename load-file-name)))
      '';
      packageRequires = [ epkgs.base16-theme ];
    };

in
{
  # Stylix may be controlling your system palette; keep the Emacs target on.
  stylix.targets.emacs.enable = true;

  # Make sure Emacs sees early-init in both common locations.
  xdg.configFile."emacs/early-init.el".text = earlyInitEl;
  home.file.".emacs.d/early-init.el".text = earlyInitEl;

  programs.emacs = {
    enable = true;

    # pgtk build (adjust if you target another build)
    package = (pkgs.emacsPackagesFor pkgs.emacs30-pgtk).emacsWithPackages (
      epkgs:
      let
        onoThemePkgs = lib.mapAttrsToList (_: scheme: mkBase16Theme epkgs scheme) onoSchemes;

        core = with epkgs; [
          base16-theme
          doom-modeline
          nerd-icons
          dashboard

          # UI / minibuffer
          vertico
          orderless
          marginalia
          consult
          general
          which-key
          popper
          shackle

          # optional UI candy used by hypermodern-ui (safe to remove)
          dimmer
          solaire-mode
          ligature
          mixed-pitch
          olivetti
          org-modern
          nerd-icons-completion

          # quality of life
          rg
          direnv
          vterm
          eat

          # keep your own stack as you like
          magit
          forge
        ];

        optional =
          (maybe epkgs "embark")
          ++ (maybe epkgs "embark-consult")
          ++ (maybe epkgs "atomic-chrome")
          ++ (maybe epkgs "elfeed")
          ++ (maybe epkgs "ement")
          ++ (maybe epkgs "telega")
          ++ (maybe epkgs "mastodon")
          ++ (maybe epkgs "pdf-tools")
          ++ (maybe epkgs "nov")
          ++ (maybe epkgs "gptel")
          ++ (maybe epkgs "format-all")
          ++ (maybe epkgs "lsp-mode")
          ++ (maybe epkgs "lsp-ui")
          ++ (maybe epkgs "treesit-auto");

      in
      onoThemePkgs ++ core ++ optional
    );

    extraConfig = ''
      ;; ------------------------------------------------------------
      ;; Load local libs from ./lib (includes hypermodern-ui)
      ;; ------------------------------------------------------------
      (add-to-list 'load-path "${localLibs}/share/emacs/site-lisp")
      (dolist (file (directory-files "${localLibs}/share/emacs/site-lisp" t "\\.el$"))
        (load file nil 'nomessage))

      ;; ------------------------------------------------------------
      ;; Your init.el (in this repo)
      ;; ------------------------------------------------------------
      ${initEl}
    '';
  };

  home.packages = with pkgs; [
    localLibs

    # Tools the UI expects (optional, but great)
    ripgrep
    fd
    rclone
    pass
    gnupg

    # Fonts: minimal default, big universe available
    iosevka
    jetbrains-mono
    inter

    # Icons: either nerd-icons fonts or all-the-icons fonts
    emacs-all-the-icons-fonts
  ];
}
