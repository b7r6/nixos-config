--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--                                       // hypermodern // topology // schema
--  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
--
--  Typed schema for the fleet topology registry. Dhall validates this at
--  evaluation (well-typed, total) BEFORE it is rendered to JSON for Nix — so a
--  malformed host can't reach the build. See
--  docs/src/architecture/networking.md for the model.
--
--  This is the single source of truth that supersedes the host lists scattered
--  across keys.nix / lib/monitors.nix / configurations/default.nix. The build
--  order downstream (CoreDNS zones, nginx vhosts, cloudflared ingress) all
--  derives from here.
let Provider = < tailscale | latitude | nube | gce | other >

let Host =
      { Type =
          { --  the NixOS attr name (configurations/nixos/<physical>)
            physical : Text
          , --  Tailscale MagicDNS short label (suffix added centrally, never here)
            tailnet : Text
          , --  the stable internal name (the <id>.<role>.<…>.<domain> scheme;
            --  placeholder until the naming scheme + domain are settled)
            logical : Text
          , --  internal (tailnet) address — what CoreDNS serves internally
            tailnet_ipv4 : Text
          , --  public/provider address — null on a NAT'd tailnet-only host
            provider_ipv4 : Optional Text
          , --  coordination/locality grouping (forward-compat; "home" for now)
            zone : Text
          , --  coarse machine kind: workstation | server | laptop | accelerator
            role : Text
          , --  service tags this host runs (drives DNS service CNAMEs etc.)
            services : List Text
          , --  is this host a managed nixosConfiguration we deploy to?
            managed : Bool
          }
      , default =
        { provider_ipv4 = None Text, services = [] : List Text, managed = True }
      }

let Zone =
      { Type = { name : Text, description : Text }, default.description = "" }

let Registry =
      { Type =
          { --  the tailnet MagicDNS suffix — the ONE place it is named in this
            --  tree; mirrors hyper-modern-nixos.network.tailnet.domain.
            tailnetSuffix : Text
          , --  the internal logical-DNS domain (placeholder; pending the real one)
            internalDomain : Text
          , zones : List Zone.Type
          , hosts : List Host.Type
          }
      , --  all fields required; default empty so `::` is usable without supplying
        --  unwanted defaults.
        default =
        {=}
      }

in  { Provider, Host, Zone, Registry }
