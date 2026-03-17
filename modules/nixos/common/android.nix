# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // android
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Android development tools and ADB configuration.
#
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.android-tools ];

  # Udev rules for Android devices
  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "android-udev-rules";
      destination = "/etc/udev/rules.d/51-android.rules";
      text = ''
        # Google devices (Pixel, Nexus, etc.)
        SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="adbusers"
      '';
    })
  ];

  users.groups.adbusers = { };
}
