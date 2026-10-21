# railgun — per-screen PREVIEW hosts for the design program.
#
#   nlp-<screen>.s4.gl  root /var/www/preview/nl-<screen>, plus every data
#                       location of nativelink.s4.gl (/ch/ /nix/ /api/ ...)
#   fgp-<screen>.s4.gl  root /var/www/preview/fg-<screen>, plus the forge API
#                       locations of forge.s4.gl
#
# Each screen agent builds its own worktree into its own root with `ui-preview`
# and shoots it with `ui-shoot`, so builds run in parallel and the live
# nativelink.s4.gl / forge.s4.gl stay on `main` until the design lead merges.
# The *.s4.gl wildcard cert covers both patterns. Nothing publishes these names:
# ui-shoot maps *.s4.gl to loopback itself.
{ config, lib, pkgs, ... }:
let
  previewRoot = "/var/www/preview";
  vhosts = config.services.nginx.virtualHosts;
  dataLocations = host: removeAttrs vhosts.${host}.locations [ "/" ];
  spa = root: {
    inherit root;
    extraConfig = ''
      autoindex off;
      try_files $uri $uri/ /index.html;
      add_header Cache-Control "no-store";
    '';
  };
  preview = prefix: host: dir: {
    serverName = "~^${prefix}-(?<screen>[a-z0-9]+)\\.s4\\.gl$";
    forceSSL = true;
    useACMEHost = "s4.gl-wildcard";
    locations = dataLocations host // { "/" = spa "${previewRoot}/${dir}-$screen"; };
  };

  uiPreview = pkgs.writeShellApplication {
    name = "ui-preview";
    runtimeInputs = with pkgs; [ nodejs_24 purescript esbuild git rsync coreutils ];
    text = ''
      # usage: ui-preview <worktree>
      #   orbital-nativelink-<screen>  -> https://nlp-<screen>.s4.gl
      #   orbital-www-<screen>         -> https://fgp-<screen>.s4.gl
      # Builds IN PLACE (incremental spago output stays in the worktree) and
      # installs dist/ to the screen's own preview root. No lock needed.
      set -euo pipefail
      wt=$(realpath "''${1:?usage: ui-preview <worktree>}")
      name=$(basename "$wt")
      case "$name" in
        orbital-nativelink-*) screen=''${name#orbital-nativelink-}; proj="$wt"; dest=${previewRoot}/nl-$screen; url=https://nlp-$screen.s4.gl/ ;;
        orbital-www-*) screen=''${name#orbital-www-}; proj="$wt/projects/orbital-forge"; dest=${previewRoot}/fg-$screen; url=https://fgp-$screen.s4.gl/
          export ORBITAL_FORGE_API_BASE="https://fgp-$screen.s4.gl/api/forge/v1" ;;
        *) echo "ui-preview: $name is not an orbital-nativelink-* or orbital-www-* worktree" >&2; exit 2 ;;
      esac
      cd "$proj"
      [ -e node_modules ] || npm ci --no-audit --no-fund
      npm run build
      install -d -m 755 "$dest"
      rsync -a --delete dist/ "$dest"/
      echo "preview: $url  ($(git -C "$wt" rev-parse --short HEAD)$(git -C "$wt" diff --quiet HEAD || echo +dirty))"
    '';
  };

  uiShoot = pkgs.writeShellApplication {
    name = "ui-shoot";
    runtimeInputs = with pkgs; [ chromium coreutils ];
    text = ''
      # usage: ui-shoot <out.png> <width> <height> <url> [virtual-time-ms]
      # Headless Chromium with *.s4.gl mapped to loopback and a throwaway
      # profile per call, so any number of agents can shoot at once.
      set -euo pipefail
      out=$1 w=$2 h=$3 url=$4 budget=''${5:-7000}
      mkdir -p "$(dirname "$out")"
      profile=$(mktemp -d)
      trap 'rm -rf "$profile"' EXIT
      chromium --headless=new --no-sandbox --hide-scrollbars --user-data-dir="$profile" \
        --window-size="$w,$h" --host-resolver-rules="MAP *.s4.gl 127.0.0.1" \
        --virtual-time-budget="$budget" --screenshot="$out" "$url" >/dev/null 2>&1
      [ -s "$out" ] && echo "$out"
    '';
  };
in
{
  services.nginx.virtualHosts.nl-preview = preview "nlp" "nativelink.s4.gl" "nl";
  services.nginx.virtualHosts.fg-preview = preview "fgp" "forge.s4.gl" "fg";

  systemd.tmpfiles.rules = [ "d ${previewRoot} 0755 b7r6 users -" ];

  environment.systemPackages = [ uiPreview uiShoot ];
}
