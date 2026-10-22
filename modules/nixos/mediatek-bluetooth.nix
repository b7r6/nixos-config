# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // mediatek-bluetooth
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Stability workarounds for the Bluetooth half of the MediaTek MT7925 combo
# radio (btusb, USB 0489:e11e / 0e8d:0717). Sibling to mediatek-wifi.nix,
# which covers the mt7925e Wi-Fi half — same silicon, different driver and
# entirely different failure modes, so they gate separately.
#
#   1. btusb enable_autosuspend=0 — the controller runtime-suspends after 2 s
#      idle (power/control=auto, autosuspend_delay_ms=2000). On Ryzen hosts the
#      MT792x remote-wakeup path is unreliable, so the suspend/resume cycle
#      shows up as audio dropouts, stalled A2DP, and br-connection-page-timeout
#      when re-connecting an already-paired device.
#
#   2. HSP/HFP roles OFF — the headset (mic) profiles are UNUSABLE on this
#      controller. Its firmware reports the (e)SCO link on a bogus sentinel
#      handle 0x0E00 and then delivers 60 bytes of 0x00 on every frame: the
#      Transparent-mode RX path is broken in firmware, so the mic yields pure
#      silence no matter which headset is attached. Upstream report:
#      https://github.com/bluez/bluetooth-next/pull/744 (no fix merged; it
#      needs a MediaTek firmware change, not a kernel one).
#
#      Leaving HFP advertised is actively harmful rather than merely useless:
#      anything that opens a mic (Google Meet, Zoom, Discord) makes WirePlumber
#      autoswitch the headset out of A2DP into HFP, where the SCO transport
#      fails in a loop —
#        spa.bluez5: Failure in Bluetooth audio transport .../fd0
#      — taking the *working* A2DP playback down with it until the link drops
#      entirely. Dropping the roles keeps the headset in A2DP permanently; mic
#      input falls through to the built-in analog capture, which is what you
#      want on a call anyway.
#
#      This is a controller-level defect, so it is disabled adapter-wide rather
#      than per-device. Flip disableHeadsetProfiles if MediaTek ever ships
#      fixed firmware.
#
# Enable on any host that ships this radio:
#   hyper-modern-nixos.mediatekBluetooth.enable = true;
{ config, lib, ... }:
let
  cfg = config.hyper-modern-nixos.mediatekBluetooth;
in
{
  options.hyper-modern-nixos.mediatekBluetooth = {
    enable = lib.mkEnableOption "MediaTek MT7925 Bluetooth stability workarounds" // {
      default = false;
    };

    disableAutosuspend = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Pass btusb enable_autosuspend=0. USB runtime suspend on this
        controller causes audio dropouts and connection page timeouts;
        keeping it awake costs a little idle power.
      '';
    };

    disableHeadsetProfiles = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Drop the HSP/HFP (headset mic) roles from the Bluetooth stack. The
        MT7925 firmware's (e)SCO receive path is broken, so these profiles
        only ever produce silence — and letting an app autoswitch into them
        breaks working A2DP playback. Set false if firmware is ever fixed.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.extraModprobeConfig = lib.mkIf cfg.disableAutosuspend ''
      options btusb enable_autosuspend=0
    '';

    services.pipewire.wireplumber.extraConfig = lib.mkIf cfg.disableHeadsetProfiles {
      "51-mediatek-no-headset-profiles" = {
        # Upstream default is
        #   [ a2dp_sink a2dp_source bap_sink bap_source hfp_hf hfp_ag ]
        # i.e. A2DP + LE Audio + HFP (HSP is already off by default). Keep
        # everything except the two HFP roles, so no headset endpoint is ever
        # registered and the device offers A2DP only.
        "monitor.bluez.properties" = {
          "bluez5.roles" = [
            "a2dp_sink"
            "a2dp_source"
            "bap_sink"
            "bap_source"
          ];
        };

        # Belt-and-braces: this setting ("switch to headset mode when
        # recording") defaults to TRUE and is what drags a connected headset
        # out of A2DP the moment anything opens a capture stream. With the HFP
        # roles gone it has nothing to switch to, but turning it off keeps the
        # intent explicit and survives re-enabling a role above.
        "wireplumber.settings" = {
          "bluetooth.autoswitch-to-headset-profile" = false;
        };
      };
    };
  };
}
