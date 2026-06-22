# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                  // hyper-modern-nixos // pinchflat + curl_cffi
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Thin overlay on the official Pinchflat image that adds `curl_cffi` to the
# system Python so the bundled yt-dlp (a Python *script* running under the
# image's /usr/bin/python3, NOT a PyInstaller binary) gains browser
# IMPERSONATION targets. SoundCloud increasingly requires impersonation; without
# curl_cffi yt-dlp reports all targets "(unavailable)" and SoundCloud extraction
# degrades. This single dep is the only gap for SoundCloud support — Pinchflat's
# source model already allows non-YouTube URLs (upstream's own "tenuous support"
# comment in sources/source.ex).
#
# Base is pulled from the FLEET zot registry (already mirrored), so the build is
# reproducible from our own infra and doesn't re-hit ghcr.
#
# Build + push (run from this dir; see also justfile/notes):
#   docker build -t registry.sju1.s4.gl/kieraneglin/pinchflat:v2025.6.6-cffi .
#   docker push  registry.sju1.s4.gl/kieraneglin/pinchflat:v2025.6.6-cffi
ARG BASE=registry.sju1.s4.gl/kieraneglin/pinchflat:v2025.6.6
FROM ${BASE}

# Debian bookworm marks system Python externally-managed (PEP 668); bootstrap
# pip via apt and install curl_cffi with --break-system-packages (we WANT it in
# the system interpreter that yt-dlp uses). Clean apt lists to keep the layer
# small. Verify at build time that impersonation is actually available so a
# broken layer fails the build instead of shipping silently.
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-pip \
 && pip3 install --break-system-packages --no-cache-dir curl_cffi \
 && apt-get purge -y python3-pip \
 && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/* \
 && python3 -c "import curl_cffi; print('curl_cffi', curl_cffi.__version__)" \
 && yt-dlp --list-impersonate-targets | grep -qi 'curl_cffi$' \
 && echo "OK: impersonation available"
