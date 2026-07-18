# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                          // hyper-modern-nixos // checks // ono-sendai-parity
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The Lean4 generator (modules/flake/themes/packages/ono-sendai-generator/) is
# the definition of truth for the palette math; lib.nix is a reimplementation
# that Stylix and the wallpaper pipeline consume at eval time. Integer HSL→RGB
# has enough rounding edges that the two CAN drift silently (the legacy
# hand-tuned palettes already did, by one bit of blue).
#
# This check pins them together: the Lean binary emits its conformance vectors
# at build time; the SAME parameter grid is evaluated through lib.nix at eval
# time; every slot of every palette must agree exactly. The grid covers both
# polarities (ono-sendai dark levels, maas white levels), the warm-paper ramp
# override, and a hue spread that exercises all six HSL sectors.
#
# Vector ORDER must match Lean's generateVectors: darks hue-major then level;
# lights hue-major, then level, then ramp.
{ pkgs }:
let
  lib = pkgs.lib;
  themeLib = import ../modules/flake/themes/lib.nix { inherit lib; };
  generator = pkgs.callPackage ../modules/flake/themes/packages/ono-sendai-generator { };

  hues = [
    { h = 211; a = 201; }
    { h = 36; a = 26; }
    { h = 0; a = 350; }
    { h = 120; a = 110; }
    { h = 262; a = 252; }
    { h = 300; a = 290; }
  ];
  darkLevels = [ "void" "deep" "night" "carbon" "github" ];
  whiteLevels = [ "tessier" "neoform" "ghost" ];
  ramps = [ 211 36 ];

  darkVectors = lib.concatMap (
    hu:
    map (
      level:
      themeLib.make-palette {
        inherit level;
        hero-hue = hu.h;
        axis-hue = hu.a;
      }
      // {
        slug = "ono-sendai-${level}";
      }
    ) darkLevels
  ) hues;

  lightVectors = lib.concatMap (
    hu:
    lib.concatMap (
      level:
      map (
        ramp:
        themeLib.make-palette-light {
          inherit level;
          hero-hue = hu.h;
          axis-hue = hu.a;
          ramp-hue = ramp;
        }
        // {
          slug = "maas-${level}";
        }
      ) ramps
    ) whiteLevels
  ) hues;

  nixVectors = pkgs.writeText "nix-vectors.json" (builtins.toJSON (darkVectors ++ lightVectors));

  compare = pkgs.writeText "compare.py" ''
    import json, sys

    lean = json.load(open(sys.argv[1]))
    nix = json.load(open(sys.argv[2]))
    slots = [f"base{n:02X}" for n in range(16)]

    assert len(lean) == len(nix), f"vector count: lean={len(lean)} nix={len(nix)}"

    bad = 0
    for lv, nv in zip(lean, nix):
        for s in slots:
            if lv[s] != nv[s]:
                bad += 1
                print(
                    f"MISMATCH {lv['slug']} hero={lv['heroHue']} axis={lv['axisHue']} "
                    f"ramp={lv['rampHue']} {s}: lean={lv[s]} nix={nv[s]}"
                )

    total = len(lean) * len(slots)
    print(f"{total - bad}/{total} slots agree across {len(lean)} vectors")
    sys.exit(1 if bad else 0)
  '';
in
pkgs.runCommand "ono-sendai-parity"
  {
    nativeBuildInputs = [
      pkgs.python3
      generator
    ];
  }
  ''
    ono-sendai-gen vectors > lean-vectors.json
    python3 ${compare} lean-vectors.json ${nixVectors}
    touch $out
  ''
