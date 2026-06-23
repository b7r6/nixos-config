# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                  // hyper-modern-nixos // drop
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# `drop` — "gh gist create" for arbitrary files via the R2 share bucket. Copies
# file(s) under a fresh unguessable token directory in the dropbox FUSE mount and
# prints the public URL(s). The token IS the capability: the bucket is public but
# NOT listable, so an unguessable key == an effectively private share.
#
# The mount root + public domain are baked in at build time from the module
# (DROP_MOUNT / DROP_DOMAIN / DROP_PREFIX), but remain env-overridable.
{
  writeShellApplication,
  coreutils,
  dropMount ? "/mnt/r2/drop",
  dropDomain ? "drop.s4.gl",
  dropPrefix ? "d",
}:
writeShellApplication {
  name = "drop";
  runtimeInputs = [ coreutils ];
  text = ''
    DROP_MOUNT="''${DROP_MOUNT:-${dropMount}}"
    DROP_DOMAIN="''${DROP_DOMAIN:-${dropDomain}}"
    DROP_PREFIX="''${DROP_PREFIX:-${dropPrefix}}"

    die() { echo "drop: $*" >&2; exit 1; }

    # url-safe lowercase base32 token from 16 random bytes (~26 chars, 128-bit).
    mint_token() {
      head -c 16 /dev/urandom | base32 | tr '[:upper:]' '[:lower:]' | tr -d '='
    }

    # percent-encode a path segment for the URL (spaces, unicode, etc.).
    urlencode() {
      local s="$1" out="" c i
      for (( i=0; i<''${#s}; i++ )); do
        c="''${s:$i:1}"
        case "$c" in
          [a-zA-Z0-9.~_-]) out+="$c" ;;
          *) out+=$(printf '%%%02X' "'$c") ;;
        esac
      done
      printf '%s' "$out"
    }

    url_for() { # token, filename
      printf 'https://%s/%s/%s/%s\n' "$DROP_DOMAIN" "$DROP_PREFIX" "$1" "$(urlencode "$2")"
    }

    cmd_ls() {
      [ -d "$DROP_MOUNT/$DROP_PREFIX" ] || { echo "(no drops)"; return 0; }
      local t
      for t in "$DROP_MOUNT/$DROP_PREFIX"/*/; do
        [ -d "$t" ] || continue
        t="$(basename "$t")"
        echo "$t"
        ( cd "$DROP_MOUNT/$DROP_PREFIX/$t" && for f in *; do [ -e "$f" ] && echo "    $(url_for "$t" "$f")"; done )
      done
    }

    cmd_rm() {
      local tok="$1" dir="$DROP_MOUNT/$DROP_PREFIX/$1"
      [ -d "$dir" ] || die "no such drop: $tok"
      rm -rf -- "$dir"
      echo "revoked: $tok"
    }

    cmd_put() {
      local token="$1"; shift
      [ -d "$DROP_MOUNT" ] || die "dropbox mount not present: $DROP_MOUNT (is hyper-modern-nixos.dropbox enabled + mounted?)"
      local dir="$DROP_MOUNT/$DROP_PREFIX/$token"
      mkdir -p "$dir"
      local f base
      for f in "$@"; do
        [ -f "$f" ] || die "not a file: $f"
        base="$(basename "$f")"
        cp -- "$f" "$dir/$base"
        url_for "$token" "$base"
      done
    }

    [ $# -ge 1 ] || die "usage: drop <path>... | -t <token> <path>... | --ls | --rm <token>"
    case "$1" in
      --ls) cmd_ls ;;
      --rm) shift; [ $# -eq 1 ] || die "--rm needs a token"; cmd_rm "$1" ;;
      -t|--token) shift; [ $# -ge 2 ] || die "-t needs a token and at least one file"
                  tok="$1"; shift; cmd_put "$tok" "$@" ;;
      -*) die "unknown option: $1" ;;
      *) cmd_put "$(mint_token)" "$@" ;;
    esac
  '';
}
