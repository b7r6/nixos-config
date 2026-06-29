# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // greetd
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Greetd login manager with tuigreet for Hyprland.
#
# fixes:
# - waits for multi-user.target so the login prompt doesn't get scribbled
#   on by services still starting
# - disables user linger for the greeter user so switch-to-configuration
#   doesn't try to reload its (non-existent) dbus session, which causes
#   a spurious exit-4 on remote nixos-rebuild switches
{ pkgs, ... }: {
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "greeter";
      };
    };
  };

  # wait for all services before showing the login prompt
  systemd.services.greetd = {
    after = [ "multi-user.target" ];
    wants = [ "multi-user.target" ];
  };

  # prevent the greeter system user from having a lingering user session.
  # without this, switch-to-configuration tries to reload user units for uid
  # 989 (greeter), fails to connect to its dbus socket, and reports exit 4.
  systemd.tmpfiles.rules = [
    "r /var/lib/systemd/linger/greeter"
  ];
}
