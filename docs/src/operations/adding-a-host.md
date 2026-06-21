# Adding a host

A NixOS host is **one entry in the `hosts` table** plus a
`configurations/nixos/<host>/` directory, then key + secret wiring. The flake
machinery in `configurations/default.nix` does the rest (`mkHost` builds each
entry into a `nixosConfiguration`).

## 1. Create the host directory

```
configurations/nixos/<host>/
├── configuration.nix          # the actual host config
├── default.nix                # imports the shared module set + configuration.nix
└── hardware-configuration.nix # from `nixos-generate-config` on the box
```

`default.nix` is boilerplate — copy it verbatim (see
`configurations/nixos/guccimane/default.nix`):

```nix
{ flake, ... }:
let
  inherit (flake) inputs;
  inherit (inputs) self;
in
{
  imports = [
    self.nixosModules.default   # the whole hyper-modern-nixos module set
    ./configuration.nix
  ];
}
```

`configuration.nix` destructures `{ flake, ... }` and imports its hardware
config plus the agenix module (pattern from
`configurations/nixos/guccimane/configuration.nix`):

```nix
{ flake, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./hardware-configuration.nix
    inputs.agenix.nixosModules.default
  ];

  networking.hostName = "<host>";
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # users (b7r6 etc.), SSH keys, groups, nix settings, the attic client cache,
  # tailscale, the firewall — all come from self.nixosModules.default. You only
  # add what's host-specific here.

  system.stateVersion = "25.05";
}
```

Users, SSH `authorizedKeys`, groups, and `nix.settings` come from the fleet-wide
`hyper-modern-nixos.users` model (`modules/nixos/myusers.nix`) — don't redeclare
`users.users` per host.

## 2. Register the host

Add it to the `hosts` table in `configurations/default.nix`:

```nix
hosts = {
  ultraviolence = { };
  watchtower    = { };
  # ...
  <host>        = { };                    # x86_64-linux (the default)
  shimmer.system = "aarch64-linux";       # aarch64 hosts set system explicitly
};
```

`system` defaults to `x86_64-linux`; set `<host>.system = "aarch64-linux"` for
ARM boxes (the DGX `shimmer` does this).

## 3. Scan + add the host key, then rekey secrets

Secrets are encrypted to recipient public keys listed in `secrets/keys.nix`
(single source of truth). A new host can only decrypt secrets once **its
ed25519 host key is listed there** and every `.age` file has been re-keyed to
include it.

```bash
# from the secrets devshell, or via flake app:
nix run .#scan-host-key <host>        # ssh-keyscan -t ed25519 over the tailnet
```

Paste the printed line under `hosts.<host>` in `secrets/keys.nix`:

```nix
hosts = {
  # ...
  <host> = [ "ssh-ed25519 AAAA...the scanned key..." ];
};
```

Then re-encrypt every secret to the updated recipient set:

```bash
nix run .#rekey-secrets               # runs `agenix -r`
```

See [Secrets (agenix)](../infrastructure/secrets.md) for the recipient model
(`mkGlobalSecret` encrypts to all user keys + every configured host).

> If the box isn't reachable yet, you can read the key on the host itself with
> `ssh <host> cat /etc/ssh/ssh_host_ed25519_key.pub` and paste the
> `key-type key` pair. Hosts with no key listed (e.g. a powered-down laptop) are
> simply skipped by `configuredHosts` in `secrets/secrets.nix`.

## 4. Wire the Tailscale safety net

So a rebuild can't strand the box off the tailnet, declare the auth-key secret
and point the option at it (pattern from `watchtower`):

```nix
age.secrets.tailscale-auth-key.file =
  ../../../secrets/agenix/machines/tailscale-auth-key.age;

hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";
```

The key must be **reusable + pre-authorized** (ideally tagged, `ephemeral=false`)
from the Tailscale admin console. See
[Tailscale](../infrastructure/tailscale.md).

## 5. Build + deploy

```bash
nixos-rebuild build --flake .#<host>                 # eval + cache hit, no activate
nixos-rebuild switch --flake .#<host> \
  --target-host <host> --use-remote-sudo             # activate over the tailnet
```

See [Deploying a host](./deploying.md) for the dry-run and staged-rollout
patterns, and [The fleet](../architecture/fleet.md) for what each box does.
