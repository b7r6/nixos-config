# railgun — ORBITAL // FORGE: Forgejo (git.s4.gl, org `straylight`), the
# orbital-forge-backend (the stable /api/forge/v1 read contract over Forgejo)
# and the Halogen UI at forge.s4.gl.
#
#   git.s4.gl    nginx → 127.0.0.1:3200 (Forgejo); git+ssh on 2222 (builtin)
#   forge.s4.gl  nginx: / → /var/www/forge (static bundle), /api/forge/ → :3210
#                (same origin, so the browser never needs CORS; the origin is
#                allowlisted on the backend anyway)
#
# Forgejo rides the fleet postgres over the unix socket with peer auth (the
# `forgejo` role owns the `forgejo` database), so there is no DB password.
# The UI bundle is built ON railgun (spago pulls the package registry at build
# time; not a pure derivation today): see the `forge-ui-build` script below.
{ flake, pkgs, lib, ... }:
let
  forgeSrc = "${flake.inputs.orbital-forge}/projects/orbital-forge";
  webRoot = "/var/www/forge";
  forgeCheckout = "/home/b7r6/src/hypermodern/orbital-www"; # vendored monorepo, see forge-ui-build
  # One-shot UI build: ORBITAL_FORGE_API_BASE must be https (build-site.mjs
  # enforces it); nginx serves /api/forge/ on the same origin.
  forgeUiBuild = pkgs.writeShellApplication {
    name = "forge-ui-build";
    runtimeInputs = with pkgs; [
      nodejs_24
      purescript
      esbuild
      git
      rsync
      coreutils
    ];
    text = ''
      set -euo pipefail
      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      # Source: the vendored monorepo checkout (git.s4.gl/straylight/orbital-www,
      # upstream hypermodern-src/orbital-straylight-www @ debdc51) so screen-level
      # design work lands without a flake bump; spago.yaml points at ../hydrogen,
      # so take the whole projects/ dir. FORGE_UI_SRC overrides; falls back to
      # the flake input when the checkout is absent.
      src="''${FORGE_UI_SRC:-${forgeCheckout}}"
      if [ -d "$src/projects/orbital-forge" ]; then
        rsync -a --exclude node_modules --exclude output --exclude .spago --exclude dist --exclude .build --exclude .git "$src/projects/" "$work/projects/"
        echo "forge ui source: $src ($(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo untracked))"
      else
        cp -r ${flake.inputs.orbital-forge}/.. "$work/projects"
        echo "forge ui source: flake input (checkout $src absent)"
      fi
      chmod -R u+w "$work"
      cd "$work/projects/orbital-forge"
      export HOME="$work/home"; mkdir -p "$HOME"
      export ORBITAL_FORGE_API_BASE="https://forge.s4.gl/api/forge/v1"
      npm ci --no-audit --no-fund
      npm run build
      out=$(ls -d dist 2>/dev/null || ls -d build 2>/dev/null || ls -d .vercel/output/static 2>/dev/null)
      sudo install -d -m 755 ${webRoot}
      sudo rsync -a --delete "$out"/ ${webRoot}/
      sudo chown -R root:root ${webRoot}
      echo "forge ui installed to ${webRoot} from $out"
    '';
  };
in
{
  imports = [ flake.inputs.orbital-forge.nixosModules.default ];

  # ── Forgejo ────────────────────────────────────────────────────────────────
  hyper-modern-nixos.databases.postgres = {
    ensureDatabases = [ "forgejo" ];
    ensureUsers = [
      {
        name = "forgejo";
        ensureDBOwnership = true;
      }
    ];
  };

  services.forgejo = {
    enable = true;
    stateDir = "/var/lib/forgejo";
    database = {
      type = "postgres";
      host = "/run/postgresql"; # unix socket, peer auth as `forgejo`
      name = "forgejo";
      user = "forgejo";
      createDatabase = false; # the fleet postgres module ensures it
    };
    settings = {
      DEFAULT.APP_NAME = "straylight";
      server = {
        DOMAIN = "git.s4.gl";
        ROOT_URL = "https://git.s4.gl/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3200;
        SSH_DOMAIN = "git.s4.gl";
        # Forgejo's builtin SSH on 2222 (railgun's sshd owns 22): the clone
        # panel advertises ssh://forgejo@git.s4.gl:2222/… and it must work.
        DISABLE_SSH = false;
        START_SSH_SERVER = true;
        BUILTIN_SSH_SERVER_USER = "forgejo";
        SSH_PORT = 2222;
        SSH_LISTEN_PORT = 2222;
        SSH_LISTEN_HOST = "0.0.0.0";
        LANDING_PAGE = "explore";
      };
      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = false;
      };
      repository.DEFAULT_BRANCH = "main";
      mirror = {
        ENABLED = true;
        DEFAULT_INTERVAL = "1h";
        MIN_INTERVAL = "10m";
      };
      session.PROVIDER = "db";
      cache.ADAPTER = "memory";
      log.LEVEL = "Info";
      metrics.ENABLED = true;
      "ui.meta" = {
        AUTHOR = "straylight";
        DESCRIPTION = "straylight — the forge";
      };
    };
  };
  systemd.services.forgejo = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };

  # ── ORBITAL // FORGE backend ───────────────────────────────────────────────
  services.orbital-forge-backend = {
    enable = true;
    port = 3210;
    upstreamBaseUrl = "http://127.0.0.1:3200/api/v1";
    organization = "straylight";
    allowedOrigins = [ "https://forge.s4.gl" ];
  };

  # ── The UI (static) + its API on the same origin ───────────────────────────
  # The reverseProxy module owns the forge.s4.gl vhost (root = webRoot, see
  # ./default.nix); these locations merge into it.
  services.nginx.virtualHosts."forge.s4.gl".locations = {
    "/api/forge/" = {
      proxyPass = "http://127.0.0.1:3210/api/forge/";
      proxyWebsockets = false;
      extraConfig = ''
        proxy_buffering off;
        proxy_request_buffering off;
      '';
    };
    "/healthz" = {
      proxyPass = "http://127.0.0.1:3210/healthz";
    };
    # SPA: client-side routes fall back to the shell
    "/".extraConfig = lib.mkAfter "try_files $uri $uri/ /index.html;";
  };
  # git over ssh (Forgejo builtin, port 2222): every interface; the Azure NSG
  # admits it from the internet, like 22.
  networking.firewall.allowedTCPPorts = [ 2222 ];

  # placeholder until forge-ui-build has run, so nginx never 404s the root
  systemd.tmpfiles.rules = [ "d ${webRoot} 0755 root root -" ];

  environment.systemPackages = [ forgeUiBuild ];
}
