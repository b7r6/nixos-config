# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // packages
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

#
# System-wide packages available to all users.
#
{ pkgs, ... }:
{
  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    # ── Core utilities ────────────────────────────────────────────────────────

    cacert
    curl
    wget
    git
    git-lfs
    unzip
    xz
    tree
    jq

    # ── Editors ───────────────────────────────────────────────────────────────

    vim
    neovim

    # ── Modern CLI tools ──────────────────────────────────────────────────────

    bat
    btop
    fd
    fzf
    ripgrep
    zoxide
    atuin
    lf
    gitui
    gh
    tmux

    # ── System tools ──────────────────────────────────────────────────────────

    home-manager
    dbus
    dconf
    pciutils

    # ── Python ────────────────────────────────────────────────────────────────

    python312

    # ── GPU monitoring ────────────────────────────────────────────────────────

    nvtopPackages.nvidia

    # ── Network analysis ──────────────────────────────────────────────────────

    wireshark
    wireshark-cli
  ];

  # Wireshark group for packet capture
  users.groups.wireshark = { };
}
