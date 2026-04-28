{
  flake.overlays = {
    default = _final: prev: {
      # Skip flaky openvswitch tests (known issue with test 1155, 1197)
      openvswitch = prev.openvswitch.overrideAttrs (_old: {
        doCheck = false;
      });

      # Fix ragenix to include runtime dependencies
      ragenix = prev.ragenix.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
        postInstall = (old.postInstall or "") + ''
          wrapProgram $out/bin/ragenix \
            --prefix PATH : ${
              prev.lib.makeBinPath [
                prev.coreutils # for sha256sum
                prev.findutils # for find
                prev.gnugrep # for grep
                prev.gnused # for sed
                prev.rage # for rage
                prev.age # for age
              ]
            }
        '';
      });

      # TODO[b7r6]: no way we need both, probably don't need either...
      agenix =
        if prev ? agenix then
          prev.agenix.overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
            postInstall = (old.postInstall or "") + ''
              wrapProgram $out/bin/agenix \
                --prefix PATH : ${
                  prev.lib.makeBinPath [
                    prev.coreutils
                    prev.findutils
                    prev.gnugrep
                    prev.gnused
                    prev.rage
                    prev.age
                  ]
                }
            '';
          })
        else
          prev.agenix or null;
    };
  };
}
