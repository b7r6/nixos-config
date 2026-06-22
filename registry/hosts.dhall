--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                        // hypermodern // topology // hosts
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  The fleet, as data. The SINGLE source of truth for host topology. Adding a
--  host = one entry here (+ its configurations/nixos/<name>/). Everything
--  downstream (CoreDNS, nginx, cloudflared) derives from this.
--
--  PLACEHOLDERS (swap in ONE place when settled — see networking.md "Open
--  decisions"):
--    - `internalDomain`  : the real internal logical-DNS domain.
--    - each `logical`    : the <id>.<role>.<region>.<zone>.<domain> scheme.
--  tailnet_ipv4 values are REAL (read from the live tailnet). provider_ipv4 is
--  None everywhere today (NAT'd tailnet-only fleet); set it when a host gets a
--  public address (e.g. on a Latitude bare-metal move).
let schema = ./schema.dhall

let Host = schema.Host

let internalDomain = "straylight.internal"

let logicalOf = \(physical : Text) -> "${physical}.${internalDomain}"

in  schema.Registry::{
    , tailnetSuffix = "osiris-walleye.ts.net"
    , internalDomain
    , zones =
      [ schema.Zone::{
        , name = "home"
        , description = "single-site homelab tailnet (pre-distribution)"
        }
      ]
    , hosts =
      [ Host::{
        , physical = "watchtower"
        , tailnet = "watchtower"
        , logical = logicalOf "watchtower"
        , tailnet_ipv4 = "100.122.228.122"
        , zone = "home"
        , role = "server"
        , services = [ "postgres", "attic", "registry", "monitoring" ]
        }
      , Host::{
        , physical = "ultraviolence"
        , tailnet = "ultraviolence"
        , logical = logicalOf "ultraviolence"
        , tailnet_ipv4 = "100.71.82.73"
        , zone = "home"
        , role = "workstation"
        , services = [ "nativelink", "searxng", "torrents", "attic-replica" ]
        }
      , Host::{
        , physical = "shimmer"
        , tailnet = "shimmer"
        , logical = logicalOf "shimmer"
        , tailnet_ipv4 = "100.116.42.95"
        , zone = "home"
        , role = "accelerator"
        , services = [] : List Text
        }
      , Host::{
        , physical = "guccimane"
        , tailnet = "guccimane"
        , logical = logicalOf "guccimane"
        , tailnet_ipv4 = "100.89.101.109"
        , zone = "home"
        , role = "workstation"
        , services = [] : List Text
        }
      , Host::{
        , physical = "shannon"
        , tailnet = "shannon"
        , logical = logicalOf "shannon"
        , tailnet_ipv4 = "100.120.215.82"
        , zone = "home"
        , role = "laptop"
        , services = [] : List Text
        }
      , Host::{
        , physical = "weyl"
        , tailnet = "weyl"
        , logical = logicalOf "weyl"
        , tailnet_ipv4 = "100.111.80.81"
        , zone = "home"
        , role = "workstation"
        , services = [] : List Text
        }
      , Host::{
        , physical = "gossamer"
        , tailnet = "gossamer"
        , logical = logicalOf "gossamer"
        , tailnet_ipv4 = "100.110.55.28"
        , zone = "home"
        , role = "accelerator"
        , services = [ "attic-client" ]
        , managed = False
        }
      ]
    }
