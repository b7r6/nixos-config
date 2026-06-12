{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
in
{
  nix = {
    package = pkgs.nixVersions.stable;

    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

    extraOptions = ''
      experimental-features = nix-command flakes pipe-operators
    '';

    settings = {
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "@wheel"
      ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = true;

  nixpkgs.overlays = [
    inputs.nix-vscode-extensions.overlays.default
    # python312 doc build broken (Sphinx/docutils 0.22 on py3.13)
    (
      final: prev:
      let
        orig-python312 = prev.python312;
      in
      {
        python312 = orig-python312.overrideAttrs (old: {
          passthru = (old.passthru or { }) // {
            doc = final.runCommand "python312-doc" { } ''
              mkdir -p $out/share/doc/python3.12-html
              echo "<html><body>stub</body></html>" > $out/share/doc/python3.12-html/index.html
            '';
          };
        });
      }
    )
  ];
}
