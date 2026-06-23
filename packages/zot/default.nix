# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                    // hyper-modern-nixos // zot
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# zot — a production-ready, vendor-neutral OCI image registry. Not in nixpkgs,
# so we package it: a single static Go binary (`./cmd/zot`).
#
# We build the MINIMAL flavour deliberately: S3/remote storage is CORE in zot
# (not an extension), so the R2-backed registry needs none of the heavy
# extensions — and skipping them avoids the `zui` npm build and the
# search/sync/trivy dependency surface entirely. Flip `extensions` on later if
# the web UI / CVE search is wanted (that path additionally needs the zui build).
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
let
  version = "2.1.17";
in
buildGoModule (_finalAttrs: {
  pname = "zot";
  inherit version;

  src = fetchFromGitHub {
    owner = "project-zot";
    repo = "zot";
    rev = "v${version}";
    hash = "sha256-/1QEMpDq8okaVWhaynlJ+tE1b6AObUnHfHrmnylBKL0=";
  };

  vendorHash = "sha256-09LQKBKyqpgBbC44VPsZ3RJcwrHWy6TpF87u35UgcYI=";

  # zot's Makefile pins GOEXPERIMENT=jsonv2; the build uses CGO-free PIE.
  env.GOEXPERIMENT = "jsonv2";
  env.CGO_ENABLED = "0";

  subPackages = [ "cmd/zot" ];

  # Match the upstream `binary-minimal` target: no extension build tags, static.
  tags = [ ];
  ldflags = [
    "-s"
    "-w"
    "-X zotregistry.dev/zot/v2/pkg/buildinfo.ReleaseTag=v${version}"
    "-X zotregistry.dev/zot/v2/pkg/buildinfo.BinaryType=minimal"
  ];
  buildmode = "pie";

  # The binary is cmd/zot → `zot`.
  postInstall = ''
    if [ -e "$out/bin/cmd" ]; then mv "$out/bin/cmd" "$out/bin/zot"; fi
  '';

  doCheck = false; # upstream tests need skopeo/docker/network; not for packaging.

  meta = {
    description = "Production-ready vendor-neutral OCI image registry (minimal build)";
    homepage = "https://zotregistry.dev";
    license = lib.licenses.asl20;
    mainProgram = "zot";
    platforms = lib.platforms.linux;
  };
})
