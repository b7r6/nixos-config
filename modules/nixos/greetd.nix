# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // greetd
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Greetd login manager with tuigreet for Hyprland.
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
