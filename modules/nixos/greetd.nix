# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // greetd
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Greetd login manager with tuigreet for Hyprland.
{ pkgs, ... }:
let
  # Session launcher (the `start-hyprland` the new-suzuki branch referenced
  # but never shipped). Two jobs beyond bare `Hyprland`:
  #   - seed the session identity vars greeters don't set
  #   - route the compositor's stdout/stderr into the journal — otherwise
  #     Hyprland's log output from a greetd session goes nowhere
  start-hyprland = pkgs.writeShellScriptBin "start-hyprland" ''
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=Hyprland
    exec systemd-cat --identifier=hyprland Hyprland "$@"
  '';
in
{
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd ${start-hyprland}/bin/start-hyprland";
        user = "greeter";
      };
    };
  };

  # also on PATH so a bare TTY login can start the same session by hand
  environment.systemPackages = [ start-hyprland ];

  # greetd holds a logind session for the greeter user. switch-to-
  # configuration-ng reloads user units for every logind-active user, which
  # needs that user's manager (and its dbus socket) running — linger keeps
  # user@<uid>.service alive without hard-coding the dynamically-allocated uid.
  users.users.greeter.linger = true;

  # wait for multi-user.target (no scribble on the login prompt)
  systemd.services.greetd.after = [ "multi-user.target" ];
}
