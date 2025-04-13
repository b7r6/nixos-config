{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default
    self.nixosModules.gui
    ./configuration.nix
  ];

  # TODO[b7r6]: generalize this...
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

  # Create the adbusers group
  users.groups.adbusers = { };

  # Add your user to the adbusers group
  users.users.b7r6.extraGroups = [ "adbusers" ];

  # Include Android tools in system packages
  programs.adb.enable = true;

  # If using android-nixpkgs, you can include this part
  # This assumes you have android-nixpkgs set up in your imports
  # android-nixpkgs.androidenv = {
  #   includeSystemPackages = true;
  # };
}
