# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                  // hypermodern-nixos // media
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Two self-hosted media servers, each independently gated, OFF BY DEFAULT:
#
#   - navidrome : music. A single Go binary serving a web player + the Subsonic
#     API on :4533. The natural fit for a tag-driven track/mix collection (every
#     mobile Subsonic client speaks to it). Reads `libraryRoot/music`.
#   - jellyfin  : video (+ music if you want one app). Web UI on :8096, native
#     Android/Google-TV client, and HARDWARE TRANSCODING via the host NVIDIA
#     stack (NVENC/NVDEC on the 5090) so 4K streams don't melt a CPU core. Reads
#     `libraryRoot/video` (point its libraries wherever in the UI).
#
# ── library on disk ────────────────────────────────────────────────────────
#
# Both read a plain directory tree rooted at `libraryRoot` (default
# /var/lib/media). That dir is declared ONCE here as an `authoritative` state
# dir (hyper-modern-nixos.state.dirs), from which the fleet plumbing DERIVES:
#   - restic backup        (state.authoritativePaths → backup.nix)
#   - impermanence persist  (state.persistPaths      → impermanence.nix)
# so nothing in backup.nix / impermanence.nix needs editing — the class carries
# the semantics. See modules/nixos/state.nix.
#
# ── reachability ───────────────────────────────────────────────────────────
#
# The fleet firewall trusts tailscale0 wholesale (modules/nixos/network.nix), so
# tailnet clients (phone/laptop) reach these ports with NO extra rule. A Google
# TV / Chromecast can't join the tailnet without sideloading, so for it we ALSO
# open the ports on the LAN interface (`lanInterface`). Set openLan = false to
# go tailnet-only.
#
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.media;
in
{
  options.hyper-modern-nixos.media = {
    enableNavidrome = lib.mkEnableOption "Navidrome music server (web + Subsonic API)";
    enableJellyfin = lib.mkEnableOption "Jellyfin video/music server (web + Google-TV, NVENC)";

    libraryRoot = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/media";

      description = ''
        Root of the media tree both servers read. Declared as an `authoritative`
        state dir, so it is backed up (restic→R2) and persisted across an
        impermanence reboot automatically. Convention:
          ''${libraryRoot}/music  → Navidrome
          ''${libraryRoot}/video  → Jellyfin
      '';
    };

    navidromePort = lib.mkOption {
      type = lib.types.port;
      default = 4533;
      description = "Port the Navidrome web/Subsonic server listens on.";
    };

    jellyfinPort = lib.mkOption {
      type = lib.types.port;
      default = 8096;
      description = "Port the Jellyfin HTTP server listens on (8096 is its default).";
    };

    openLan = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open the enabled servers' ports on the LAN interface so a Google TV /
        Chromecast (which is NOT on the tailnet) can reach them. Tailnet clients
        work regardless (tailscale0 is a trusted interface fleet-wide). Set false
        for tailnet-only.
      '';
    };

    lanInterface = lib.mkOption {
      type = lib.types.str;
      default = "enp113s0";
      description = "LAN interface on which to open ports when openLan is true.";
    };

    hardwareAcceleration = lib.mkOption {
      type = lib.types.bool;
      default = config.hyper-modern-nixos.nvidia.enable or false;

      description = ''
        Wire Jellyfin for NVIDIA hardware transcoding (NVENC/NVDEC). Defaults to
        on whenever the host nvidia module is enabled. Requires
        hyper-modern-nixos.nvidia.enable (which provides hardware.graphics +
        the driver); the actual codec selection (NVENC) is set in the Jellyfin
        admin UI → Playback → Transcoding.
      '';
    };
  };

  config = lib.mkIf (cfg.enableNavidrome || cfg.enableJellyfin) {
    # ── single source of truth for the on-disk library ──────────────────────
    # authoritative ⇒ restic-backed AND impermanence-persisted (derived in
    # state.nix; consumed by backup.nix + impermanence.nix). One declaration.
    hyper-modern-nixos.state.dirs.media = {
      path = cfg.libraryRoot;
      class = "authoritative";
    };

    # Ensure the library subtree exists with sane ownership BEFORE the services
    # start. Group-readable so both service users (navidrome, jellyfin) can read
    # a shared tree; tmpfiles is idempotent and runs early.
    systemd.tmpfiles.rules = [
      "d ${cfg.libraryRoot}        0755 root root - -"
      "d ${cfg.libraryRoot}/music  0755 root root - -"
      "d ${cfg.libraryRoot}/video  0755 root root - -"
    ];

    # ── Navidrome (music) ────────────────────────────────────────────────────

    services.navidrome = lib.mkIf cfg.enableNavidrome {
      enable = true;
      settings = {
        MusicFolder = "${cfg.libraryRoot}/music";

        # Bind loopback only — nginx handles TLS and oauth2-proxy gates access.
        Address = "127.0.0.1";
        Port = cfg.navidromePort;

        # Trust the X-User header from oauth2-proxy for SSO (no double login).
        # nginx passes it after auth_request validates the session with kanidm.
        ReverseProxyUserHeader = "X-User";
        ReverseProxyWhitelist = "127.0.0.1/32";

        # SoundCloud-style rips often lack album tags; let folder structure and
        # filenames carry the library so single tracks/mixes still show up.
        Scanner.Extractor = "taglib";
      };
    };

    # ── Jellyfin (video + music, Google-TV client, NVENC) ─────────────────────

    services.jellyfin = lib.mkIf cfg.enableJellyfin {
      enable = true;
      openFirewall = false; # we manage exposure ourselves (tailnet + optional LAN)
    };

    # jellyfin-ffmpeg with NVENC + the render node access the service user needs
    # for hardware transcoding. The nvidia module already provides the driver +
    # hardware.graphics; here we just put the jellyfin user in render/video so it
    # can open /dev/dri/renderD* and the NVIDIA devices.
    users.users.jellyfin.extraGroups = lib.mkIf (cfg.enableJellyfin && cfg.hardwareAcceleration) [
      "render"
      "video"
    ];

    # ── firewall: LAN only (tailnet is already trusted fleet-wide) ────────────
    # Single entry for the LAN interface — both TCP and UDP keys live under the
    # one dynamic attr (Nix forbids defining the same dynamic key twice).
    networking.firewall.interfaces = lib.mkIf cfg.openLan {
      ${cfg.lanInterface} = {
        allowedTCPPorts =
          lib.optional cfg.enableNavidrome cfg.navidromePort
          ++ lib.optionals cfg.enableJellyfin [
            cfg.jellyfinPort
            8920 # Jellyfin HTTPS (if enabled in-app)
          ];
        # Jellyfin client auto-discovery (DLNA/clients) over the LAN.
        allowedUDPPorts = lib.optionals cfg.enableJellyfin [
          1900 # DLNA / SSDP discovery
          7359 # Jellyfin client auto-discovery
        ];
      };
    };
  };
}
