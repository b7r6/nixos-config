# retired dashboards

Dashboards whose data source no longer exists on any live host. They still
render (the `grafana-dashboards` check walks this directory too) and still
provision, but into a `retired` Grafana folder so the top level only shows
dashboards that have something to say.

| dashboard          | why it is here                                              |
|--------------------|-------------------------------------------------------------|
| attic              | attic replica retired with the 2026-10-07 sell-off          |
| backup-pitr        | postgres PITR; no postgres on the fleet                     |
| forgejo-activity   | self-hosted forge retired with watchtower                   |
| kanidm-identity    | the IdP retired with watchtower                             |
| oci-registry       | zot retired with watchtower                                 |
| supabase-postgres  | no postgres on the fleet                                    |
| exit-rotation      | tailscale-exit-rotate.timer runs on no live host            |
| coredns            | role parked in shannon's disabled block; move back when restored |

Moving one back: `git mv retired/<x>.dhall .` and flip `../../schema/` to
`../schema/` in its imports.
