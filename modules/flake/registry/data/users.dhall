-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                              // hypermodern // registry // users
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
-- the fleet's user registry. SINGLE source of truth for identity.
-- adding a user = one entry here + rebuild. everything derives:
--   - kanidm account provisioning (passkey-first, OIDC-capable)
--   - SSH authorized_keys on every permitted host
--   - agenix secret recipients (admin group can decrypt all)
--   - grafana OIDC role mapping
--   - forgejo OIDC group membership
--   - NixOS users.users declarations

let Group =
      < fleet_admins      -- full sudo, all secrets, all services
      | fleet_users       -- SSH access, basic service access
      | forgejo_users     -- can auth to forgejo via OIDC
      | grafana_admins    -- grafana admin role (vs viewer)
      | build_users       -- can submit to nativelink remote execution
      >

let User =
      { Type =
          { name : Text
          , displayName : Text
          , email : Text
          , recovery : Text
          , sshKeys : List Text
          , groups : List Group
          , hosts : List Text
          , passkeys : Bool
          }
      , default =
          { name = ""
          , displayName = ""
          , email = ""
          , recovery = ""
          , sshKeys = [] : List Text
          , groups = [ Group.fleet_users, Group.forgejo_users ]
          , hosts = [] : List Text    -- empty = all hosts
          , passkeys = True
          }
      }

-- ── the fleet ──────────────────────────────────────────────────────────────────

let users =
      [ User::{
        , name = "b7r6"
        , displayName = "b7r6"
        , email = "b7r6@straylight.software"
        , recovery = "b7r6@proton.me"
        , sshKeys =
            [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINbn+XF6n9v9VKLFGLBVz+G1LyL6GlcgZbIwhP89PPsp"
            , "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ1ptqyz5C3YCcMgh3LUbXtjeS1rIZ5/6RHnH7D93Nqf"
            , "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILBEaqZY7H09brD/syW20HVDpYmKf44TOZ/Whzemwc/+"
            ]
        , groups =
            [ Group.fleet_admins
            , Group.forgejo_users
            , Group.grafana_admins
            , Group.build_users
            ]
        , hosts = [] : List Text  -- all hosts
        , passkeys = True
        }
      ]

in  { Group, User, users }
