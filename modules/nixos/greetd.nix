# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // greetd
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Greetd login manager with tuigreet for Hyprland.
#
# KNOWN ISSUE: switch-to-configuration-ng exits 4 on remote switches because
# the greeter system user (uid 989) has a running user@.service slice but no
# dbus socket. The activation treats this as a failure even though it's harmless.
# This is an upstream NixOS bug — the activation should tolerate system users
# without functioning user sessions. The deploy script handles this by treating
# exit 4 with only "user activation for greeter failed" as success.
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

  # wait for all services before drawing the login prompt
  systemd.services.greetd.after = [ "multi-user.target" ];
}
