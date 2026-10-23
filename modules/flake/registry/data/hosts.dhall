--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                             // hypermodern // topology // hosts
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  The fleet, as data. The SINGLE source of truth for host topology. Adding a
--  host = one entry here (+ its configurations/nixos/<name>/). Everything
--  downstream (CoreDNS, nginx, cloudflared) derives from this.
--
--  Naming scheme: logical = <physical>.<dc>.s4.gl, where <dc> is the nearest
--  Equinix DC code (e.g. sju1 = San Juan). s4.gl is our real domain (Njalla), so
--  internal names can get real DNS-01 ACME certs. The fleet is single-site (sju1)
--  today; new DCs become new subdomains under s4.gl with no restructuring.
--
--  tailnet_ipv4 values are REAL (read from the live tailnet). provider_ipv4 is
--  None everywhere today (NAT'd tailnet-only fleet); set it when a host gets a
--  public address (e.g. on a Latitude bare-metal move). The Tailscale MagicDNS
--  suffix (tailnetSuffix) is a SEPARATE namespace from s4.gl.
--
--  lan_ipv4 (the <host>.lan.<dc>.s4.gl mode, so non-tailnet LAN devices like the
--  Google TV can reach Jellyfin etc.): the current DHCP leases of the WIRED NICs,
--  used as-is (the router is a vendor black box; not statically reserving yet). If
--  the router reshuffles a lease, it's a one-line edit here. Laptops (shannon,
--  weyl) stay None (roam / no stable lease); gossamer stays None for now (DGX-OS
--  spark; future PXE-install test case).
--
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
let schema = ./schema.dhall

let Host = schema.Host

let internalDomain = "s4.gl"

let logicalOf =
      \(physical : Text) ->
      \(dc : Text) ->
        "${physical}.${dc}.${internalDomain}"

in  schema.Registry::{
    , tailnetSuffix = "osiris-walleye.ts.net"
    , internalDomain
    , zones =
      [ schema.Zone::{
        , name = "sju1"
        , description = "San Juan (single-site homelab; nearest Equinix = sju1)"
        }
      , schema.Zone::{
        , name = "sk1"
        , description = "Stockholm (Azure swedencentral; nearest Equinix = sk1) — railgun, the dev box"
        }
      , schema.Zone::{
        , name = "wa1"
        , description = "Warsaw (Azure polandcentral; nearest Equinix = wa1) — nl-wa1-a, a NativeLink cache node"
        }
      , schema.Zone::{
        , name = "va1"
        , description = "Ashburn (Azure eastus; Equinix is dc1 there, va1 so it does not read as 'DC one') — nl-va1-a, a NativeLink cache node"
        }
      , schema.Zone::{
        , name = "px1"
        , description = "Phoenix (Azure westus3; nearest Equinix = ph1, px1 after the airport) — nl-px1-a, a NativeLink cache node"
        }
      ]
    , hosts =
      [ Host::{
        , physical = "watchtower"
        , tailnet = "watchtower"
        , dc = "sju1"
        , logical = logicalOf "watchtower" "sju1"
        , tailnet_ipv4 = "100.122.228.122"
        , lan_ipv4 = Some "192.168.40.98"
        , zone = "sju1"
        , role = "server"
        , services =
          [ "postgres"
          , "attic"
          , "registry"
          , "studio"
          -- `git` moved to railgun 2026-10-17, `auth` (Kanidm) 2026-10-21
          -- (watchtower sold 2026-10-07)
          ]
        }
      , Host::{
        , physical = "ultraviolence"
        , tailnet = "ultraviolence"
        , dc = "sju1"
        , logical = logicalOf "ultraviolence" "sju1"
        , tailnet_ipv4 = "100.71.82.73"
        , lan_ipv4 = Some "192.168.40.115"
        , zone = "sju1"
        , role = "workstation"
        , -- sold 2026-10-07; `nativelink` dropped (railgun owns the tag now)
          services =
          [ "searxng"
          , "torrents"
          , "attic-replica"
          ]
        }
      , Host::{
        , physical = "shimmer"
        , tailnet = "shimmer"
        , dc = "sju1"
        , logical = logicalOf "shimmer" "sju1"
        , tailnet_ipv4 = "100.116.42.95"
        , lan_ipv4 = Some "192.168.40.232"
        , zone = "sju1"
        , role = "accelerator"
        , services = [] : List Text
        }
      , Host::{
        , physical = "guccimane"
        , tailnet = "guccimane"
        , dc = "sju1"
        , logical = logicalOf "guccimane" "sju1"
        , tailnet_ipv4 = "100.89.101.109"
        , lan_ipv4 = Some "192.168.40.81"
        , zone = "sju1"
        , role = "server"
        , services =
          [ "drop", "navidrome", "jellyfin", "pinchflat" ]
        }
      , Host::{
        , physical = "railgun"
        , tailnet = "railgun"
        , dc = "sk1"
        , logical = logicalOf "railgun" "sk1"
        , tailnet_ipv4 = "100.76.101.10"
        , provider_ipv4 = Some "20.91.238.153"
        , zone = "sk1"
        , role = "server"
        , services = [ "nativelink", "ch", "grafana", "monitoring", "git", "forge", "auth" ]
        }
      , -- nl-wa1-a: a NativeLink cache node (2026-10-23) — its own one-host site in
        -- the Dhall fleet, a producer of the shared R2 Nix cache. Azure, 64 vCPU,
        -- 2 TiB disk; the public address is the install/deploy path from railgun.
        Host::{
        , physical = "nl-wa1-a"
        , tailnet = "nl-wa1-a"
        , dc = "wa1"
        , logical = logicalOf "nl-wa1-a" "wa1"
        , tailnet_ipv4 = "100.91.107.49"
        , provider_ipv4 = Some "74.248.20.192"
        , zone = "wa1"
        , role = "server"
        , services = [] : List Text
        }
      , -- nl-va1-a: a NativeLink cache node (2026-10-23) — its own one-host site in
        -- the Dhall fleet, a producer of the shared R2 Nix cache. Azure, 64 vCPU,
        -- 2 TiB disk; the public address is the install/deploy path from railgun.
        Host::{
        , physical = "nl-va1-a"
        , tailnet = "nl-va1-a"
        , dc = "va1"
        , logical = logicalOf "nl-va1-a" "va1"
        , tailnet_ipv4 = "100.101.38.5"
        , provider_ipv4 = Some "20.85.225.135"
        , zone = "va1"
        , role = "server"
        , services = [] : List Text
        }
      , -- nl-px1-a: a NativeLink cache node (2026-10-23) — its own one-host site in
        -- the Dhall fleet, a producer of the shared R2 Nix cache. Azure, 64 vCPU,
        -- 2 TiB disk; the public address is the install/deploy path from railgun.
        Host::{
        , physical = "nl-px1-a"
        , tailnet = "nl-px1-a"
        , dc = "px1"
        , logical = logicalOf "nl-px1-a" "px1"
        , tailnet_ipv4 = "100.105.126.42"
        , provider_ipv4 = Some "20.118.184.142"
        , zone = "px1"
        , role = "server"
        , services = [] : List Text
        }
      , Host::{
        , physical = "shannon"
        , tailnet = "shannon"
        , dc = "sju1"
        , logical = logicalOf "shannon" "sju1"
        , tailnet_ipv4 = "100.113.120.45"
        , zone = "sju1"
        , role = "laptop"
        , -- 2026-10-17: the services moved to railgun (the Azure box); shannon
          -- is a laptop again. Its own ClickHouse/Grafana keep running until
          -- its next deploy, which will point its agent at railgun's gateway.
          -- `clickhouse-keeper` stays: shannon's Keeper is registry-derived and
          -- must find itself in the ensemble (railgun's is an explicit solo).
          services = [ "clickhouse-keeper" ]
        }
      , Host::{
        , physical = "weyl"
        , tailnet = "weyl"
        , dc = "sju1"
        , logical = logicalOf "weyl" "sju1"
        , tailnet_ipv4 = "100.111.80.81"
        , zone = "sju1"
        , role = "laptop"
        , services = [] : List Text
        }
      , Host::{
        , physical = "gossamer"
        , tailnet = "gossamer"
        , dc = "sju1"
        , logical = logicalOf "gossamer" "sju1"
        , tailnet_ipv4 = "100.110.55.28"
        , zone = "sju1"
        , role = "accelerator"
        , services = [ "attic-client" ]
        , managed = False
        }
      ]
    }
