# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                               // hyper-modern-nixos // narsil
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# narsil on the PATH, plus the one-word launcher the editors need.
#
# The LSP is `narsil lsp` (a subcommand over stdio). VS Code's Nix IDE
# extension only takes a bare `nix.serverPath` — no arguments — so we ship a
# `narsil-lsp` wrapper for any client that can't pass argv. Emacs (lsp-mode)
# and the CLI use `narsil` directly.
{
  config,
  flake,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.narsil;

  narsil = flake.inputs.narsil.packages.${pkgs.stdenv.hostPlatform.system}.narsil;

  narsil-lsp = pkgs.writeShellScriptBin "narsil-lsp" ''
    exec ${narsil}/bin/narsil lsp "$@"
  '';
in
{
  options.hyper-modern-nixos.narsil = {
    enable = lib.mkEnableOption "narsil (Nix+bash HM type checker, linter, LSP)" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      narsil
      narsil-lsp
    ];
  };
}
