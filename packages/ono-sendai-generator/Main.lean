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

def main (args : List String) : IO Unit := do
  match args with
  | ["json", level, hero, axis] =>
    -- Single palette JSON output for Nix
    let lvl := parseLevel level
    let h := hero.toNat?.getD 211
    let a := axis.toNat?.getD 201
    IO.println (generateJson lvl h a)

  | ["json-all", hero, axis] =>
    -- All levels JSON for Nix
    let h := hero.toNat?.getD 211
    let a := axis.toNat?.getD 201
    IO.println (generateAllLevelsJson h a)

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
    IO.println "  ono-sendai-gen json [level] [hero] [axis]  — JSON palette for Nix"
    IO.println "  ono-sendai-gen json-all [hero] [axis]      — All levels as JSON"
    IO.println "  ono-sendai-gen emacs [level] [hero] [axis] — Emacs theme"
    IO.println "  ono-sendai-gen nvim-palette                — Neovim palette.lua"
    IO.println "  ono-sendai-gen nvim-init                   — Neovim init.lua"
    IO.println "  ono-sendai-gen nvim-plugin                 — Neovim plugin"
    IO.println ""
    IO.println "Levels: void, deep, night, carbon, github"
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
    writeFile s!"{outDir}/nix/all-palettes.json" (generateAllLevelsJson defaultHero defaultAxis)

    IO.println ""
    IO.println "done. hero=211° axis=201°"
