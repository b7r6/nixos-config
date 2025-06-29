{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [ self.homeModules.default ];

  me = {
    username = "gedanziger";
    fullname = "gedanziger";
    email = "gedanziger@gmail.com";
  };

  # TODO[b7r6]: this probably belongs in a central place
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
  home.stateVersion = "25.05";
}
