-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                        // hypermodern // nixos // nix-compile
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- nix-compile configuration for this NixOS config repository.
--
-- We use the strict profile but disable lisp-case enforcement since this is
-- a NixOS/home-manager configuration that must interface with nixpkgs APIs
-- which use camelCase and snake_case conventions.
--
let Severity = < Error | Warning | Info | Off >

let RuleOverride = { id : Text, severity : Severity, reason : Optional Text }

let override-with-reason =
      \(id : Text) ->
      \(severity : Severity) ->
      \(reason : Text) ->
        { id, severity, reason = Some reason } : RuleOverride

in  { profile = "strict"
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
    }
