# Overview

This repo is a **bog-standard [flake-parts](https://flake.parts) configuration**. It used to be
built on `nixos-unified` (autoWire); that has been torn out. There is no magic auto-discovery
framework anymore — the wiring is explicit Nix in `flake.nix`, `configurations/default.nix`, and
`modules/flake/default.nix` (the barrel).

## Top-level layout

```
flake.nix                  # mkFlake entrypoint; inputs; systems
configurations/
  default.nix              # the fleet wiring: hosts table + mkHost builder
  nixos/<host>/            # one dir per nixosConfiguration
  home/<user>.nix          # one file per standalone homeConfiguration
modules/
  nixos/                   # flat NixOS module files + default.nix aggregator
  home/                    # home-manager modules (default.nix aggregator)
  flake/                   # barrel + components + cross-cutting modules
    default.nix            # barrel: pkgs, overlays, imports all components
    {attic,backup,coredns,media,nativelink,registry,themes}/
                           # component subsystems (NixOS module, checks, packages, data)
    fmt.nix, devshell.nix, docs.nix, overlays.nix, deploy.nix, usb.nix
                           # cross-cutting modules
  overlays/                # the repo overlay (self.overlays.default)
packages/                  # callPackage'd derivations (e.g. ono-sendai-generator, state-audit)
secrets/                   # agenix tree + admin devshell/apps + keys.nix
docs/                      # this mdBook
```

## The flake entrypoint

`flake.nix` is minimal — it calls `flake-parts.lib.mkFlake`, takes its systems from
`nix-systems/default-linux` (`x86_64-linux` + `aarch64-linux`), and imports exactly two things:

```nix
inputs.flake-parts.lib.mkFlake { inherit inputs; } {
  systems = import inputs.systems;
  imports = [
    ./modules/flake                # barrel: pkgs/overlays, components, devshells, packages, apps, checks
    ./configurations               # the fleet: nixosConfigurations + homeConfigurations
  ];
};
```

Everything else (`agenix`, `home-manager`, `disko`, `stylix`, `nvf`, the `emacs-overlay`,
`nativelink`, …) is a flake input; most `follows` nixpkgs to keep the closure tight.

## How a `nixosConfiguration` is built

`configurations/default.nix` is the flake-parts module that replaces what nixos-unified used to
autowire. It defines the fleet as a plain attrset and maps a `mkHost` builder over it:

- **`specialArgs`** — every host/home module destructures `{ flake, ... }`, where
  `flake = { inherit self inputs config; }`. This is identical to the old nixos-unified
  `specialArgsFor.nixos`, so existing configs need no changes.
- **`mkHost name { system ? "x86_64-linux" }`** calls `nixpkgs.lib.nixosSystem` with three modules:
  1. `{ nixpkgs.hostPlatform = system; }`
  2. `homeManagerNixosModule` (home-manager as a NixOS module)
  3. `./nixos/${name}/default.nix` (the host)
- **`homeManagerNixosModule`** imports `home-manager.nixosModules.home-manager` and sets
  `useGlobalPkgs = true`, `useUserPackages = true`, and `extraSpecialArgs = specialArgs`. It
  deliberately does **not** put `homeModules.default` into `sharedModules` — that would force the
  full home config onto every HM user (e.g. test-vm's inline `test` user). Managed users pick up
  `configurations/home/<name>.nix` via the [`identity`](./module-conventions.md) module instead.

A host dir is tiny. `configurations/nixos/ultraviolence/default.nix`:

```nix
{ flake, ... }:
let inherit (flake.inputs) self; in
{
  imports = [
    self.nixosModules.default     # = ../modules/nixos (everything, gated)
    ./configuration.nix           # host specifics
  ];
}
```

`self.nixosModules.default` is the single aggregator at `modules/nixos/default.nix` that imports
every module file. Each one is **option-gated and off by default**, so importing all of them costs
nothing — a host just sets `hyper-modern-nixos.<x>.enable = true` for what it wants. See
[module conventions](./module-conventions.md).

## perSystem outputs

`modules/flake/default.nix` (the barrel) builds the `perSystem` `pkgs` (with `allowUnfree` and the
overlay stack) and imports cross-cutting modules + every component subsystem:

- `./fmt.nix` — treefmt (nixfmt/deadnix/statix, biome, ruff, shfmt, …)
- `./devshell.nix` — the default devshell + agenix-shell user-secret autoload
- `./docs.nix` — `packages.docs` (this book) + `apps.docs-serve`
- `./overlays.nix` — surfaces `self.overlays.default`
- `./themes` — fonts/stylix theme plumbing
- `./attic`, `./backup`, `./coredns`, `./media`, `./nativelink`, `./registry` — component subsystems
- `../../secrets` — the agenix admin devshell + flake apps

## Flake outputs (summary)

| Output | Source |
| --- | --- |
| `nixosConfigurations.<host>` | `mkHost` over the `hosts` table |
| `legacyPackages.<sys>.homeConfigurations.<user>` | auto-found `configurations/home/*.nix` |
| `nixosModules.{default,dgx-spark,wayland}` | `modules/nixos/*` |
| `homeModules.default` | `modules/home` |
| `packages.<sys>` | fonts, `ono-sendai-generator`, USB installer images |
| `apps.<sys>` | `deploy-fleet`, `build-usb`, `docs-serve`, `restic-init`, secret-admin apps |
| `devShells.<sys>.{default,secrets}` | `modules/flake/devshell.nix` + `secrets/` |
| `checks.<sys>` | per-component: attic-cache, backup-restic, coredns, nativelink, state-audit |

For the detailed walk-through see [flake structure](./flake-structure.md); for the machines see
[the fleet](./fleet.md).
