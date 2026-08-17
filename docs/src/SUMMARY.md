# Summary

[Introduction](./introduction.md)
[TODO frontier](./todo-frontier.md)

# Architecture

- [Overview](./architecture/overview.md)
- [Flake structure](./architecture/flake-structure.md)
- [Module conventions](./architecture/module-conventions.md)
- [The fleet](./architecture/fleet.md)
- [State & backup model](./architecture/state-and-backup.md)
- [Networking design (DNS/TLS/edge)](./architecture/networking.md)

# Infrastructure

- [Secrets (agenix)](./infrastructure/secrets.md)
- [Tailscale](./infrastructure/tailscale.md)
- [Binary cache (attic)](./infrastructure/attic.md)
  - [NAR chunk-prefetch fix](./architecture/attic-prefetch.md)
- [PostgreSQL](./infrastructure/postgres.md)
- [Backups (restic → R2)](./infrastructure/backups.md)
- [Remote execution (nativelink)](./infrastructure/nativelink.md)
- [NativeLink production architecture](./infrastructure/nativelink-production.md)
- [Nix binary cache (nativelink)](./infrastructure/nativelink-nix-cache.md)
- [ClickHouse production architecture](./infrastructure/clickhouse.md)

# Services

- [SearXNG + torrents](./services/searxng-torrents.md)
- [OCI registry (zot)](./services/registry.md)
- [Supabase (self-hosted)](./services/supabase.md)

# Media

- [Overview](./media/overview.md)
- [Servers (Navidrome + Jellyfin)](./media/servers.md)
- [Pinchflat (yt-dlp manager)](./media/pinchflat.md)
- [Dropbox (shareable file URLs)](./media/dropbox.md)
- [Library pipeline (sort/enrich/tag)](./media/pipeline.md)
- [queuedrop (browser extension)](./media/queuedrop.md)

# Operations

- [Deploying a host](./operations/deploying.md)
- [Adding a host](./operations/adding-a-host.md)
- [Dev shells](./operations/dev-shells.md)
- [Runbooks](./operations/runbooks.md)
- [btrfs ENOSPC recovery](./operations/btrfs-enospc-recovery.md)

# Reference

- [Module options](./reference/options.md)
- [Checks (NixOS tests)](./reference/checks.md)
