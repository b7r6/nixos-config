let
  inherit (import ./keys.nix) users hosts;

  allUsers = builtins.attrNames users;
  allHosts = builtins.attrNames hosts;
  mkSecret = user: hostList: (builtins.concatMap (h: hosts.${h} or [ ]) hostList) ++ users.${user};

  mkUserSecret = user: users.${user};
in
{
  "secrets/tailscale-auth-key.parabolic-surf.github.org.age".publicKeys = mkUserSecret "b7r6";
  "secrets/tailscale-auth-key.straylight-evaluation.github.org.age".publicKeys = mkUserSecret "b7r6";
  "secrets/tailscale-auth-key.v4.surf.age".publicKeys = mkUserSecret "b7r6";
  "b7r6/.netrc.age".publicKeys = mkUserSecret "b7r6";
  "b7r6/atuin-key.txt.age".publicKeys = mkUserSecret "b7r6";
}
