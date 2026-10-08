# Fleet's osquery agent (orbit) — Secureframe's device agent.
#
# The orbit binary is a STATIC Go executable (runs as-is on NixOS); orbit
# self-updates osqueryd/desktop at runtime into its --root-dir, and those
# dynamic binaries run via the host's nix-ld. Only the enroll config
# (ORBIT_ENROLL_SECRET, ORBIT_FLEET_URL) is org-specific — keep that in agenix,
# never here.
#
# Durable: the generic binary is published to the public R2 bucket behind
# cdn.s4.gl (the secret-bearing .deb is archived privately in
# straylight-archive/packages/fleet-orbit/). Refresh on a version bump with:
#   rclone copyto <orbit> straylight-r2:straylight-public-cdn/packages/fleet-orbit/<v>/orbit
#   nix store prefetch-file https://cdn.s4.gl/packages/fleet-orbit/<v>/orbit
{
  stdenv,
  fetchurl,
}:
stdenv.mkDerivation {
  pname = "fleet-orbit";
  version = "1.61.0";
  src = fetchurl {
    url = "https://cdn.s4.gl/packages/fleet-orbit/1.61.0/orbit";
    hash = "sha256-a2mGeLbLZ+9ZEqlkPpzf3070JZ2GK8KXVyVlsRtaGmA=";
  };
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  installPhase = "install -Dm755 $src $out/bin/orbit";
}
