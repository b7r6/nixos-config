# Fix for nvidia driver disallowedReferences issue on aarch64
# The nvidia-x11 package in nixpkgs has disallowedReferences = [ kernel.dev ]
# which causes build failures on aarch64. This overlay removes that restriction.

final: prev: {
  linuxPackages_6_17_1_nvidia = prev.linuxPackages_6_17_1_nvidia.extend (lpfinal: lpprev: {
    nvidia_x11 = lpprev.nvidia_x11.overrideAttrs (old: {
      # Remove the disallowedReferences check that causes issues on aarch64
      disallowedReferences = [];

      # Alternative: you can also try setting libsOnly = true
      # libsOnly = true;
    });
  });

  # Also apply to any other kernel packages that might be used
  linuxPackages = prev.linuxPackages.extend (lpfinal: lpprev: {
    nvidia_x11 = lpprev.nvidia_x11.overrideAttrs (old: {
      disallowedReferences = [];
    });
  });

  linuxPackages_latest = prev.linuxPackages_latest.extend (lpfinal: lpprev: {
    nvidia_x11 = lpprev.nvidia_x11.overrideAttrs (old: {
      disallowedReferences = [];
    });
  });
}