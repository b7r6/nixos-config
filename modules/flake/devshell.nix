{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        packages = [ pkgs.nixd ];
        shellHook = ''
          export NIXD_FLAGS="--semantic-tokens=true"
        '';
      };
    };
}
