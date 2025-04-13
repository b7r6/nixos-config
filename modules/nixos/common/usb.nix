{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    libinput
    usbtop
    usbutils
    usbview
  ];
}
