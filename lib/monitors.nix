# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // monitors
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Per-host Hyprland monitor layouts — the SINGLE SOURCE OF TRUTH.
#
# Monitor layout is plain data that both the NixOS host config and the
# standalone home-manager config need; it must be neither host-hardcoded into
# the home config nor duplicated between the two. So it lives here as data and
# is imported directly by both (the same convention lib/ono-sendai.nix uses for
# the shared color library):
#
#   - NixOS:  configurations/nixos/<host>/configuration.nix sets
#               home-manager.users.b7r6.hyper-modern-nixos.hyprland.monitors =
#                 (import ../../../lib/monitors.nix).<host>;
#   - Home:   configurations/home/b7r6.nix sets the standalone default from
#               (import ../../lib/monitors.nix).${defaultHost}
#             at mkDefault priority, so a NixOS host override always wins and
#             there is never a conflicting-definition error (e.g. shimmer vs.
#             ultraviolence).
#
# Adding a host = add one entry here. Nothing else duplicates these strings.
let
  # ── b7r6-desk: pair of ASUS PG32UCDP 4K OLEDs ────────────────────────────────
  # The physical desk, described once. Driven by shimmer (DGX Spark) over
  # HDMI; ultraviolence has moved to its own single panel (below). Hyprland
  # matches monitors by EDID description (make/model/serial), so this layout
  # applies on whichever host the panels are currently plugged into.
  # n.b. the panels do 4K@240 (DSC); 120 is the deliberate choice here.
  # scale 1.0, deliberately: at 32"/137dpi this is "large 1x" territory, and
  # on WOLED (non-standard subpixel layout) fractional-scale downsampling
  # visibly softens text. Density is handled by font sizes instead — sharp
  # glyphs beat uniformly magnified chrome for a terminal-centric workload.
  b7r6-desk = {
    left = {
      description = "ASUSTek COMPUTER INC PG32UCDP SCLMQS022729";
      resolution = "3840x2160";
      refreshRate = 120;
      position = "0x0";
      scale = 1.0;
      workspaces = [
        1
        2
        3
        4
        5
      ];
    };

    right = {
      description = "ASUSTek COMPUTER INC PG32UCDP T1LMQS044820";
      resolution = "3840x2160";
      refreshRate = 120;
      position = "3840x0";
      scale = 1.0;
      workspaces = [
        6
        7
        8
        9
        10
      ];
      primary = true;
    };
  };
in
{
  # Standalone `nh home switch` (no NixOS host context) falls back to this
  # host's layout. The primary workstation is the sane default.
  defaultHost = "ultraviolence";

  # ── ultraviolence: single LG UltraGear+ 4K over HDMI ─────────────────────────
  # 60Hz deliberately: this panel's 4K@144 path is DisplayPort-only, and the
  # bringup on 2026-09-04 showed the DP link training at 1 lane/RBR against a
  # 4-lane/HBR3 monitor (bad cable — kernel: "enabling link 1 failed: 15",
  # weston wedged on ENOMEM atomic commits, black screen). HDMI on the Granite
  # Ridge iGPU tops out at 4K@60 and is rock solid. To reclaim 144Hz: certified
  # DP 1.4 (HBR3) cable into DP-1, then bump refreshRate here.
  ultraviolence = {
    center = {
      description = "LG Electronics LG ULTRAGEAR+ 502NTMX7E483";
      resolution = "3840x2160";
      refreshRate = 60;
      position = "0x0";
      scale = 1.5;
      workspaces = [
        1
        2
        3
        4
        5
        6
        7
        8
        9
        10
      ];
      primary = true;
    };
  };

  # ── shimmer (DGX Spark): b7r6-desk over HDMI ─────────────────────────────────
  shimmer = b7r6-desk;

  # ── gossamer (DGX Spark): single 4K LG OLED ─────────────────────────────────
  gossamer = {
    center = {
      description = "";
      resolution = "3840x2160";
      refreshRate = 120;
      position = "0x0";
      scale = 1.5;
      workspaces = [
        1
        2
        3
        4
        5
        6
        7
        8
        9
        10
      ];
      primary = true;
    };
  };
}
