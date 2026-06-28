-- renders users.dhall → JSON for Nix consumption
-- dhall-to-json serializes records and lists natively, so we just need to
-- convert the Group union to Text before serialization.

let registry = ./users.dhall

let groupToText =
      \(g : registry.Group) ->
        merge
          { fleet_admins = "fleet_admins"
          , fleet_users = "fleet_users"
          , forgejo_users = "forgejo_users"
          , grafana_admins = "grafana_admins"
          , build_users = "build_users"
          }
          g

-- dhall has no List/map builtin; use List/build + List/fold
let map =
      \(a : Type) ->
      \(b : Type) ->
      \(f : a -> b) ->
      \(xs : List a) ->
        List/build
          b
          ( \(list : Type) ->
            \(cons : b -> list -> list) ->
            \(nil : list) ->
              List/fold a xs list (\(x : a) -> \(acc : list) -> cons (f x) acc) nil
          )

let renderUser =
      \(u : registry.User.Type) ->
        { name = u.name
        , displayName = u.displayName
        , email = u.email
        , recovery = u.recovery
        , sshKeys = u.sshKeys
        , groups = map registry.Group Text groupToText u.groups
        , hosts = u.hosts
        , passkeys = u.passkeys
        }

let RenderedUser =
      { name : Text
      , displayName : Text
      , email : Text
      , recovery : Text
      , sshKeys : List Text
      , groups : List Text
      , hosts : List Text
      , passkeys : Bool
      }

in  map registry.User.Type RenderedUser renderUser registry.users
