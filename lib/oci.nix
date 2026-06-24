# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                 // hyper-modern-nixos // oci
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
#   "the future is already here — it's just not very evenly distributed"
#
# OCI container extraction primitives. Turns pinned container images into native
# Nix derivations via crane(1) — no Docker runtime, no build system, just read
# out the artifacts and patch them for NixOS.
#
# ── Design ──────────────────────────────────────────────────────────────────────
#
# The key insight: container images ARE content-addressed Nix derivations wearing
# a Docker costume. crane export flattens the image layers into a rootfs tarball.
# We extract it as a fixed-output derivation (deterministic, cached), then either
# use autoPatchelfHook (for ELF binaries like BEAM releases) or just point
# Node.js at the pre-built JS (no patching needed).
#
# Two primitives:
#
#   exportImage { image, hash, platform? }
#     → FOD containing the flattened rootfs
#
#   extractBin { name, version, image, hash, appDir, runtimeInputs?, ... }
#     → derivation with /bin wrappers + patched ELF binaries
#
# ── Usage ───────────────────────────────────────────────────────────────────────
#
#   oci = import ../lib/oci.nix { inherit pkgs; };
#
#   realtime = oci.extractBin {
#     name = "supabase-realtime";
#     version = "2.102.3";
#     image = "docker.io/supabase/realtime:v2.102.3";
#     hash = "sha256-...";
#     appDir = "/app";
#     entrypoint = "bin/realtime";
#     runtimeInputs = with pkgs; [ openssl ncurses zlib ];
#   };
#
{ pkgs }:
let
  inherit (pkgs) lib stdenv;

  # ══════════════════════════════════════════════════════════════════════════════
  # exportImage — flatten an OCI image to a rootfs (fixed-output derivation)
  # ══════════════════════════════════════════════════════════════════════════════
  #
  # args:
  #   image    : full image reference (e.g. "docker.io/supabase/realtime:v2.102.3")
  #   hash     : SRI hash of the extracted rootfs tree (nix hash path)
  #   platform : OCI platform string (default: inferred from stdenv)
  #
  # returns: derivation whose $out IS the rootfs (flat directory, no tar)

  exportImage =
    {
      image,
      hash,
      platform ? (if stdenv.hostPlatform.isAarch64 then "linux/arm64" else "linux/amd64"),
    }:
    let
      safeName = builtins.replaceStrings [ "/" ":" "." ] [ "-" "-" "_" ] image;
    in
    stdenv.mkDerivation {
      name = "${safeName}-rootfs";

      nativeBuildInputs = with pkgs; [
        crane
        gnutar
      ];

      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
      outputHash = hash;

      SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

      buildCommand = ''
        mkdir -p $out
        crane export --platform ${platform} ${image} - | tar -xf - -C $out
      '';
    };

  # ══════════════════════════════════════════════════════════════════════════════
  # extractBin — extract application binaries from a container image
  # ══════════════════════════════════════════════════════════════════════════════
  #
  # args:
  #   name          : package name
  #   version       : version string
  #   image         : full image reference
  #   hash          : SRI hash of the rootfs
  #   appDir        : path within the rootfs containing the application
  #   entrypoint    : relative path (from appDir) to the main binary
  #   runtimeInputs : packages needed at runtime (for rpath)
  #   extraBins     : attrset of { name = "relative/path"; } for extra wrappers
  #   isNode        : if true, skip autoPatchelf and wrap with nodejs instead
  #   nodePackage   : which nodejs to use (default: pkgs.nodejs)
  #   platform      : OCI platform override
  #
  # returns: derivation with bin/ wrappers and the extracted app tree

  extractBin =
    {
      name,
      version,
      image,
      hash,
      appDir ? "/app",
      entrypoint,
      runtimeInputs ? [ ],
      extraBins ? { },
      isNode ? false,
      nodePackage ? pkgs.nodejs,
      platform ? null,
    }:
    let
      rootfs = exportImage (
        { inherit image hash; } // lib.optionalAttrs (platform != null) { inherit platform; }
      );

      rpath = lib.makeLibraryPath runtimeInputs;
    in
    stdenv.mkDerivation {
      pname = name;
      inherit version;
      src = rootfs;

      nativeBuildInputs = [
        pkgs.makeWrapper
      ]
      ++ lib.optionals (!isNode) [
        pkgs.autoPatchelfHook
        pkgs.patchelf
      ];

      # autoPatchelfHook searches buildInputs for needed .so files
      buildInputs = runtimeInputs;

      dontConfigure = true;
      dontBuild = true;

      # pnpm/npm hoisted symlinks can dangle when extracting a subtree from a
      # container rootfs (the targets lived outside appDir). These are dead
      # workspace artifacts that Node.js never resolves at runtime.
      dontCheckForBrokenSymlinks = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/app $out/bin

        cp -a "$src${appDir}/." $out/app/

        ${
          if isNode then
            ''
              makeWrapper ${nodePackage}/bin/node $out/bin/${name} \
                --add-flags "$out/app/${entrypoint}" \
                ${lib.optionalString (runtimeInputs != [ ]) ''--prefix LD_LIBRARY_PATH : "${rpath}"''}
            ''
          else
            ''
              makeWrapper $out/app/${entrypoint} $out/bin/${name} \
                ${lib.optionalString (rpath != "") ''--prefix LD_LIBRARY_PATH : "${rpath}"''}
            ''
        }

        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            binName: relPath:
            if isNode then
              ''
                makeWrapper ${nodePackage}/bin/node $out/bin/${binName} \
                  --add-flags "$out/app/${relPath}" \
                  ${lib.optionalString (runtimeInputs != [ ]) ''--prefix LD_LIBRARY_PATH : "${rpath}"''}
              ''
            else
              ''
                makeWrapper $out/app/${relPath} $out/bin/${binName} \
                  ${lib.optionalString (rpath != "") ''--prefix LD_LIBRARY_PATH : "${rpath}"''}
              ''
          ) extraBins
        )}

        runHook postInstall
      '';

      meta = {
        description = "${name} (extracted from OCI image)";
        platforms = [
          "x86_64-linux"
          "aarch64-linux"
        ];
      };
    };
in
{
  inherit exportImage extractBin;
}
