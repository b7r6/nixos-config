{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [ self.homeModules.default ];

  me = {
    username = "b7r6";
    fullname = "b7r6";
    email = "b7r6@b7r6.net";
  };

  # TODO[b7r6]: this probably belongs in a central place
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
  home.stateVersion = "25.05";
}
