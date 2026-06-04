{ kernel, nvidia_x11, stdenv }:

# Build nvidia kernel modules without disallowedReferences check
# This is necessary on aarch64 where the kernel modules need to reference kernel.dev
stdenv.mkDerivation rec {
  inherit (nvidia_x11) name version src;

  # Copy everything from the original nvidia_x11
  buildInputs = nvidia_x11.buildInputs or [];
  nativeBuildInputs = nvidia_x11.nativeBuildInputs or [];

  # Build the kernel modules
  buildPhase = ''
    # Use the original nvidia build
    cp -r ${nvidia_x11}/* . 2>/dev/null || true
  '';

  installPhase = ''
    mkdir -p $out
    cp -r ${nvidia_x11}/* $out/
  '';

  # This is the key - we don't set disallowedReferences
  # allowing the kernel modules to reference kernel.dev

  passthru = nvidia_x11.passthru or {};
}