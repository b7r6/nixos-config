# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // mediatek-wifi
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Stability workarounds for the MediaTek MT7925 (Filogic 360) Wi-Fi 7 radio
# (mt7925e). Two durable, independent fixes — opt-in per host because they
# only apply where that card is present, and the ASPM one trades a little
# idle power for link stability:
#
#   1. NetworkManager powersave OFF — the MT7925 drops packets / stalls the
#      link when the radio idle-sleeps.
#   2. mt7925e disable_aspm=1 — PCIe ASPM is the documented trigger for
#      random mt7925e firmware death (total radio loss until module reload).
#
# First hardened on gossamer (onboard card). Enable on any host that ships
# the same radio: hyper-modern-nixos.mediatekWifi.enable = true;
{ config, lib, ... }:
let
  cfg = config.hyper-modern-nixos.mediatekWifi;
in
{
  options.hyper-modern-nixos.mediatekWifi = {
    enable = lib.mkEnableOption "MediaTek MT7925 (Filogic 360) Wi-Fi stability workarounds" // {
      default = false;
    };

    disableAspm = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Pass mt7925e disable_aspm=1. PCIe ASPM triggers random firmware
        death on this radio; disabling it costs a little idle power.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager.wifi.powersave = false;
    boot.extraModprobeConfig = lib.mkIf cfg.disableAspm ''
      options mt7925e disable_aspm=1
    '';
  };
}
