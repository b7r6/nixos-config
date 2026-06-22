--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                        // hypermodern // topology // hosts
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
        , services = [ "postgres", "attic", "registry", "monitoring" ]
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
        , services = [ "nativelink", "searxng", "torrents", "attic-replica" ]
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
        , services = [ "drop" ]
        }
      , Host::{
        , physical = "shannon"
        , tailnet = "shannon"
        , dc = "sju1"
        , logical = logicalOf "shannon" "sju1"
        , tailnet_ipv4 = "100.120.215.82"
        , zone = "sju1"
        , role = "laptop"
        , services = [] : List Text
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
