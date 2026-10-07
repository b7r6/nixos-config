-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                             // hypermodern // nixos // narsil
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- narsil configuration for this NixOS config repository (migrated from the
-- pre-rename .nix-compile.dhall, 2026-10-07).
--
-- Strict profile, but lisp-case and the raw-nixpkgs-pattern rules are off:
-- a NixOS/home-manager config must interface with nixpkgs APIs that use
-- camelCase/snake_case and the stock mkDerivation/runCommand idioms.
--
let Severity = < Off | Info | Warning | Error >

let override-with-reason =
      \(id : Text) ->
      \(severity : Severity) ->
      \(reason : Text) ->
        { id, severity, reason = Some reason }

in  { profile = "strict"
    , layout = "flake-parts"
    , extra-ignores = [ ".direnv/**", "result", "result-*" ]
    , overrides =
      [ override-with-reason
          "non-lisp-case"
          Severity.Off
          "NixOS config must interface with nixpkgs/home-manager APIs"
      , override-with-reason
          "no-raw-mkderivation"
          Severity.Off
          "Standard nixpkgs patterns for NixOS config"
      , override-with-reason
          "no-raw-runcommand"
          Severity.Off
          "Standard nixpkgs patterns for NixOS config"
      , override-with-reason
          "no-raw-writeshellapplication"
          Severity.Off
          "Standard nixpkgs patterns for NixOS config"
      , override-with-reason
          "no-translate-attrs-outside-prelude"
          Severity.Off
          "No prelude layer in this config repo"
      , override-with-reason
          "no-substitute-all"
          Severity.Off
          "Standard nix templating for config files"
      ]
    , lsp = { max-threads = 4, max-memory-mb = 512, max-disk-mb = 1024 }
    }
