import OnoSendaiGen

open OnoSendaiGen

def parseLevel (s : String) : BlackLevel :=
  match s.toLower with
  | "void" => .void
  | "deep" => .deep
  | "night" => .night
  | "carbon" => .carbon
  | "github" => .github
  | _ => .carbon

def parseWhiteLevel (s : String) : WhiteLevel :=
  match s.toLower with
  | "tessier" => .tessier
  | "neoform" => .neoform
  | "ghost" => .ghost
  | _ => .neoform

def main (args : List String) : IO Unit := do
  match args with
  | ["json", level, hero, axis] =>
    -- Single palette JSON output for Nix
    let lvl := parseLevel level
    let h := hero.toNat?.getD 211
    let a := axis.toNat?.getD 201
    IO.println (generateJson lvl h a)

  | ["json-light", level, hero, axis, ramp] =>
    -- Single maas (light) palette, with paper-tint override (bioptic = 36)
    let lvl := parseWhiteLevel level
    let h := hero.toNat?.getD 211
    let a := axis.toNat?.getD 201
    let r := ramp.toNat?.getD 211
    IO.println (generateJsonLight lvl h a r)

  | ["json-light", level, hero, axis] =>
    let lvl := parseWhiteLevel level
    let h := hero.toNat?.getD 211
    let a := axis.toNat?.getD 201
    IO.println (generateJsonLight lvl h a)

  | ["json-light", level] =>
    IO.println (generateJsonLight (parseWhiteLevel level) 211 201)

  | ["json-light"] =>
    IO.println (generateJsonLight .neoform 211 201)

  | ["json", level] =>
    IO.println (generateJson (parseLevel level) 211 201)

  | ["json-all", hero, axis] =>
    -- All levels JSON for Nix, both polarities
    let h := hero.toNat?.getD 211
    let a := axis.toNat?.getD 201
    IO.println (generateAllLevelsJson h a)

  | ["vectors"] =>
    -- Conformance vectors: the truth every reimplementation is tested against
    IO.println generateVectors

  | ["json"] =>
    -- Default: carbon, 211, 201
    IO.println (generateJson .carbon 211 201)

  | ["emacs", level, hero, axis] =>
    let lvl := parseLevel level
    let h := hero.toNat?.getD 211
    let a := axis.toNat?.getD 201
    IO.println (generateEmacs lvl h a)

  | ["nvim-palette"] =>
    IO.println generateNvimPalette

  | ["nvim-init"] =>
    IO.println generateNvimInit

  | ["nvim-plugin"] =>
    IO.println generateNvimPlugin

  | _ =>
    -- Default: generate all editor themes
    let outDir := "out"
    let defaultHero := 211
    let defaultAxis := 201

    IO.println "// ono-sendai // base16 // plugin generator //"
    IO.println ""
    IO.println "Usage:"
    IO.println "  ono-sendai-gen json [level] [hero] [axis]              — JSON palette for Nix"
    IO.println "  ono-sendai-gen json-light [level] [hero] [axis] [ramp] — Maas (light) palette"
    IO.println "  ono-sendai-gen json-all [hero] [axis]                  — All levels, both polarities"
    IO.println "  ono-sendai-gen vectors                                 — Conformance vectors"
    IO.println "  ono-sendai-gen emacs [level] [hero] [axis]             — Emacs theme"
    IO.println "  ono-sendai-gen nvim-palette                            — Neovim palette.lua"
    IO.println "  ono-sendai-gen nvim-init                               — Neovim init.lua"
    IO.println "  ono-sendai-gen nvim-plugin                             — Neovim plugin"
    IO.println ""
    IO.println "Black levels: void, deep, night, carbon, github"
    IO.println "White levels: tessier, neoform, ghost   (bioptic = neoform + ramp 36)"
    IO.println ""

    -- Default behavior: write all files
    IO.println "── emacs ──"
    writeFile s!"{outDir}/emacs/ono-sendai-theme.el"
      (generateEmacs .carbon defaultHero defaultAxis)

    IO.println "── nvim ──"
    writeFile s!"{outDir}/nvim/lua/ono-sendai/palette.lua" generateNvimPalette
    writeFile s!"{outDir}/nvim/lua/ono-sendai/init.lua" generateNvimInit
    writeFile s!"{outDir}/nvim/plugin/ono-sendai.lua" generateNvimPlugin

    IO.println "── json (for nix) ──"
    writeFile s!"{outDir}/nix/palette.json" (generateJson .carbon defaultHero defaultAxis)
    writeFile s!"{outDir}/nix/palette-light.json" (generateJsonLight .neoform defaultHero defaultAxis)
    writeFile s!"{outDir}/nix/all-palettes.json" (generateAllLevelsJson defaultHero defaultAxis)

    IO.println "── conformance vectors ──"
    writeFile s!"{outDir}/vectors/vectors.json" generateVectors

    IO.println ""
    IO.println "done. hero=211° axis=201°"
