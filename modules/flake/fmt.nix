{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    let
      indentWidth = 2;
      lineLength = 100;
    in
    { pkgs, ... }:
    {
      treefmt = {
        programs.biome.enable = true;
        settings.formatter.biome.allowComments = true;
        settings.formatter.biome.allowTrailingCommas = true;
        settings.formatter.biome.bracketSameLine = false;
        settings.formatter.biome.bracketSpacing = false;
        settings.formatter.biome.indentStyle = "space";
        settings.formatter.biome.indentWidth = 2;
        settings.formatter.biome.json.indentWidth = 2;
        settings.formatter.biome.json.indentStyle = "space";
        settings.formatter.biome.json.trailingComma = "es5";
        settings.formatter.biome.jsxQuoteStyle = "double";
        settings.formatter.biome.lineWidth = lineLength;
        settings.formatter.biome.trailingComma = "always";

        settings.formatter.biome.ignore = [
          "launchSettings.json"
          "package.json"
        ];

        # `buildifier`: `.bzl` and `.bazel` files
        programs.buildifier.enable = true;

        # `clang-format`: C/C++, C#, Protocol Buffers, Java
        programs.clang-format.enable = true;
        programs.clang-format.includes = [
          "*.c"
          "*.h"
          "*.cpp"
          "*.cs"
          "*.proto"
          "*.java"
        ];

        # `deadnix`: dead code elimination for `nixlang`
        programs.deadnix.enable = true;

        # `dhall`
        programs.dhall.enable = true;
        programs.dhall.lint = true;

        # `dos2unix`
        programs.dos2unix.enable = true;

        # `fourmolu`: haskell formatting
        programs.fourmolu.enable = true;

        # `hlint`: haskell linter
        programs.hlint.enable = true;

        # `just`: justfiles
        programs.just.enable = true;

        # `keep-sorted`: generally tidy
        programs.keep-sorted.enable = true;

        # `mdformat`: markdown with an emphasis on `README.md` style documents
        programs.mdformat.enable = true;
        programs.mdformat.settings.number = true;
        programs.mdformat.settings.wrap = lineLength;

        # `nixfmt`: nixlang formatter...
        programs.nixfmt.enable = true;
        programs.nixfmt.strict = true;
        programs.nixfmt.width = lineLength;

        # `ruff`: best python formatter except maybe that brand-new meta stuff...
        # TODO[b7r6]: set the indent width properly...
        programs.ruff-format.enable = true;
        programs.ruff-format.lineLength = lineLength;
        programs.ruff-check.enable = true;

        # `shfmt`: bash mostly, we could consider `beautysh`
        programs.shfmt.enable = true;
        programs.shfmt.indent_size = indentWidth;

        # `statix`: static anlaysis for `nixlang`
        programs.statix.enable = true;

        # `stylish-haskell`: haskell formatting that's a little extra...
        programs.stylish-haskell.enable = true;

        # `taplo`: TOML
        programs.taplo.enable = true;

        # XML, i.e. most `dotnet`/`msbuild` configuration mostly...
        settings.formatter.xmllint = {
          command = "${pkgs.libxml2}/bin/xmllint";
          package = pkgs.libxml2;
          options = [
            "--format"
            "--encode"
            "UTF-8"
          ];
          includes = [
            "*.xml"
            "*.csproj"
            "*.props"
            "*.targets"
            "*.xaml"
          ];
        };

        # `yamlfmt`: YAML
        programs.yamlfmt.enable = true;
      };
    };
}
