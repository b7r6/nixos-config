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

  # greetd holds a logind session for the greeter user (uid 989). that session
  # needs a functioning user@989.service (with dbus socket) or switch-to-
  # configuration-ng fails when it tries to reload user units for the greeter.
  #
  # ordering:
  # - wait for multi-user.target (no scribble on the login prompt)
  # - want user@989.service (keep the greeter's user manager alive)
  systemd.services.greetd = {
    after = [
      "multi-user.target"
      "user@989.service"
    ];
    wants = [ "user@989.service" ];
  };
}
