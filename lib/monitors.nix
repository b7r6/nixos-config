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
{
  # Standalone `nh home switch` (no NixOS host context) falls back to this
  # host's layout. The primary workstation is the sane default.
  defaultHost = "ultraviolence";

  # ── ultraviolence: triple 4K (DP-5 left | DP-3 center | DP-4 right) ──────────
  ultraviolence = {
    left = {
      description = "ASUSTek COMPUTER INC PG32UCDP SCLMQS022729";
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
      ];
    };

    center = {
      description = "ASUSTek COMPUTER INC PG32UCDP T1LMQS044820";
      resolution = "3840x2160";
      refreshRate = 120;
      position = "2560x0";
      scale = 1.5;
      workspaces = [
        6
        7
        8
        9
        10
      ];
      primary = true;
    };

    right = {
      description = "LG Electronics LG ULTRAGEAR+ 502NTMX7E483";
      resolution = "3840x2160";
      refreshRate = 144;
      position = "5120x0";
      scale = 1.5;
      workspaces = [
        11
        12
        13
        14
        15
      ];
    };
  };

  # ── shimmer (DGX Spark): 1440p ultrawide center + 4K right ───────────────────
  shimmer = {
    center = {
      description = "AOC CU34G2XP 1Q1QBHA003180";
      resolution = "3440x1440";
      refreshRate = 100;
      position = "0x0";
      scale = 1.0;
      workspaces = [
        1
        2
        3
        4
        5
      ];
      primary = true;
    };

    right = {
      description = "LG Electronics LG ULTRAGEAR+ 502NTMX7E483";
      resolution = "3840x2160";
      refreshRate = 240;
      position = "3440x0";
      scale = 1.5;
      workspaces = [
        6
        7
        8
        9
        10
      ];
    };
  };

  # ── shannon (laptop): Samsung OLED 2880x1800 internal panel ─────────────────
  shannon = {
    center = {
      description = "Samsung Display Corp. ATNA33AA08-0";
      resolution = "2880x1800";
      refreshRate = 60;
      position = "0x0";
      scale = 2.0;
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
