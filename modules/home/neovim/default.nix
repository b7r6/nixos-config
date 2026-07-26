# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                               // hyper-modern-nixos // neovim
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Portable-first, same doctrine as emacs: the config LIVES in
# dotfiles/nvim (lazy.nvim, plugin-free degradation, the CI-pinned lua
# palette engine + wintermute live channel) and ~/.config/nvim is an
# out-of-store symlink into the working tree — edits land in git diff,
# no rebuild. Nix contributes the editor and PATH-resolved language
# servers; nothing breaks without it.
#
# Deliberately NOT programs.neovim: home-manager's module generates its
# own xdg.configFile."nvim/init.lua" whenever it's enabled, which
# collides with the whole-directory symlink (and for any user whose
# working tree doesn't exist yet, the dangling intermediate symlink
# fails the home-files build with "outside $HOME"). The aliases and
# EDITOR are three lines; the collision surface isn't worth them.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.neovim;
  dotfiles = config.hyper-modern-nixos.dotfiles;
in
{
  options.hyper-modern-nixos.neovim = {
    enable = lib.mkEnableOption "Neovim editor configuration";

    defaultEditor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Set Neovim as the default editor";
    };

    repoConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Symlink ~/.config/nvim to dotfiles/nvim in the working tree
        (out-of-store; the repo is home, nix only points at it).
      '';
    };

    languageServers.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        PATH-resolved language servers the config probes for with
        `executable()`. Per-project servers ride direnv devshells; this
        is just the always-there floor.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.neovim
    ]
    ++ lib.optionals cfg.languageServers.enable [
      pkgs.nixd
      pkgs.lua-language-server
    ];

    home.shellAliases = {
      vi = "nvim";
      vim = "nvim";
    };

    home.sessionVariables = lib.mkIf cfg.defaultEditor {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };

    # Divergence-safe migration, mirroring the emacs pattern: a live
    # unmanaged ~/.config/nvim is preserved to nvim.local and activation
    # PROCEEDS — never abort the whole home switch over a dotfile.
    home.activation.nvimRepoConfigMigrate = lib.mkIf cfg.repoConfig (
      lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        _nvim_dir="$HOME/.config/nvim"
        if [ -e "$_nvim_dir" ] && [ ! -L "$_nvim_dir" ]; then
          echo "hyper-modern: preserving unmanaged nvim config to nvim.local" >&2
          mv "$_nvim_dir" "$_nvim_dir.local"
        fi
      ''
    );

    xdg.configFile."nvim" = lib.mkIf cfg.repoConfig {
      source = config.lib.file.mkOutOfStoreSymlink "${dotfiles.path}/nvim";
    };

    # Cursor discipline for repoConfig = false hosts (with repoConfig the
    # same setting lives in dotfiles/nvim/init.lua)
    xdg.configFile."nvim/init.lua" = lib.mkIf (!cfg.repoConfig) {
      text = ''
        vim.o.guicursor = "a:block-blinkwait500-blinkon500-blinkoff500"
      '';
    };
  };
}
