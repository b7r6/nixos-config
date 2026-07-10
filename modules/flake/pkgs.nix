# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                        // hyper-modern-nixos // flake // pkgs
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Constructs the per-system `pkgs` used by all perSystem modules: applies the
# repo overlay, devshell, vscode-extensions, and emacs-overlay.
{ inputs, self, ... }: {
  perSystem = { system, ... }: {
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;

      config = {
        allowUnfree = true;
        allowUnfreePredicate = _: true;
      };

      overlays = [
        # Our overlay — this perSystem pkgs is what standalone homeConfigurations
        # use (and what devshells/packages use), so applying it here gives
        # standalone `nh home switch` the overlay WITHOUT setting
        # home-manager nixpkgs.overlays (which warns under useGlobalPkgs).
        # NixOS systems get it via modules/nixos/nix.nix.
        self.overlays.default

        inputs.devshell.overlays.default
        inputs.nix-vscode-extensions.overlays.default

        # opencode (anomalyco fork) -> pkgs.opencode / pkgs.opencode-desktop.
        # modules/home/llm installs it for b7r6.
        inputs.opencode.overlays.default

        # emacs-pgtk -> 31.x (master). modules/home/emacs uses it.
        inputs.emacs-overlay.overlays.default
      ];
    };
  };
}
