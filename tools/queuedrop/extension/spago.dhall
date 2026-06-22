{ name = "queuedrop"
, dependencies =
  [ "prelude"
  , "effect"
  , "console"
  , "aff"
  , "aff-promise"
  , "argonaut-core"
  , "argonaut-codecs"
  , "maybe"
  , "either"
  , "foreign-object"
  , "exceptions"
  ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs" ]
}
