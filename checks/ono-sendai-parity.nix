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
#
# When the wintermute binary (continuity input) is supplied, the gate goes
# THREE-way: the daemon's own port of the math is diffed against the same
# grid via `wintermute vectors`. The elisp port in dotfiles/emacs/
# (hypermodern-palette.el, the live in-editor theme engine) is the FOURTH
# implementation, run under `emacs --batch`. The lua port in dotfiles/nvim/
# (lua/hypermodern/palette.lua, neovim's in-editor engine) is the FIFTH,
# run under `nvim -l`.
{
  pkgs,
  wintermute ? null,
}:
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

  # hosaka pins the family-ramp path at its signature pair (78/168);
  # blackwell night ramp 165 across black levels, grace paper 150 across white
  hosakaDarkVectors = map (
    level:
    themeLib.make-palette {
      inherit level;
      family = "hosaka";
      hero-hue = 78;
      axis-hue = 168;
    }
    // {
      slug = "hosaka-blackwell-${level}";
    }
  ) darkLevels;

  hosakaLightVectors = map (
    level:
    themeLib.make-palette-light {
      inherit level;
      hero-hue = 78;
      axis-hue = 168;
      ramp-hue = 150;
    }
    // {
      slug = "hosaka-grace-${level}";
    }
  ) whiteLevels;

  nixVectors = pkgs.writeText "nix-vectors.json" (
    builtins.toJSON (darkVectors ++ lightVectors ++ hosakaDarkVectors ++ hosakaLightVectors)
  );

  compare = pkgs.writeText "compare.py" ''
    import json, sys

    lean = json.load(open(sys.argv[1]))
    others = {name: json.load(open(path))
              for name, path in (a.split("=", 1) for a in sys.argv[2:])}
    slots = [f"base{n:02X}" for n in range(16)]

    bad = 0
    for name, vs in others.items():
        assert len(lean) == len(vs), f"vector count: lean={len(lean)} {name}={len(vs)}"
        for lv, ov in zip(lean, vs):
            for s in slots:
                if lv[s] != ov[s]:
                    bad += 1
                    print(
                        f"MISMATCH [{name}] {lv['slug']} hero={lv['heroHue']} "
                        f"axis={lv['axisHue']} ramp={lv['rampHue']} {s}: "
                        f"lean={lv[s]} {name}={ov[s]}"
                    )

    total = len(lean) * len(slots) * len(others)
    print(
        f"{total - bad}/{total} slots agree across {len(lean)} vectors x "
        f"{len(others)} implementations ({', '.join(others)})"
    )
    sys.exit(1 if bad else 0)
  '';
in
pkgs.runCommand "ono-sendai-parity"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.emacs-nox
      pkgs.neovim
      generator
    ]
    ++ lib.optional (wintermute != null) wintermute;
  }
  ''
    ono-sendai-gen vectors > lean-vectors.json
    emacs --batch -l ${../dotfiles/emacs/hypermodern-palette.el} \
      --eval '(hypermodern/emit-vectors)' > elisp-vectors.json
    HOME=$TMPDIR nvim --clean --headless \
      -l ${../dotfiles/nvim/lua/hypermodern}/vectors.lua > lua-vectors.json
    ${lib.optionalString (wintermute != null) "wintermute vectors > wintermute-vectors.json"}
    python3 ${compare} lean-vectors.json \
      nix=${nixVectors} \
      elisp=elisp-vectors.json \
      lua=lua-vectors.json \
      ${lib.optionalString (wintermute != null) "wintermute=wintermute-vectors.json"}
    touch $out
  ''
