# Flake structure

A detailed walk of the three files that wire everything: `flake.nix`, `configurations/default.nix`,
and `modules/flake/default.nix` (the barrel).

## `flake.nix`

The entrypoint is `flake-parts.lib.mkFlake`. Systems come from `nix-systems/default-linux`
(`x86_64-linux`, `aarch64-linux`):

```nix
inputs.flake-parts.lib.mkFlake { inherit inputs; } {
  systems = import inputs.systems;
  imports = [
    ./modules/flake
    ./configurations
  ];
};
```

Inputs of note (most `follows` nixpkgs):

- `nixpkgs` → `sensenet-ai/nixpkgs` (the fork at HEAD, **not** upstream nixpkgs-unstable); the whole tree rides it via `follows = "nixpkgs"`
- `agenix`, `agenix-shell` — secrets at rest + devshell autoload
- `home-manager` — used both as a NixOS module and standalone
- `disko`, `impermanence`, `impurity`, `nixos-generators`
- `devshell`, `treefmt-nix` — tooling
- `emacs-overlay` — `pkgs.emacs-pgtk` tracking emacs-31 master
- `nativelink` — provides the `nativelink` binary (no upstream NixOS module)
- `stylix`, `nvf`, `nix4nvchad`, `xremap-flake`, `nix-vscode-extensions`, `nix-index-database`,
  `nix-compile`

## `configurations/default.nix`

The flake-parts module that wires the fleet. It is a function of
`{ self, inputs, config, lib, ... }`.

### specialArgs

```nix
specialArgs = { flake = { inherit self inputs config; }; };
```

This is the `{ flake, ... }` argument every host/home module destructures to reach `flake.inputs`,
`flake.self`, `flake.config`. Preserved verbatim from nixos-unified for compatibility.

### homeManagerNixosModule

```nix
homeManagerNixosModule = {
  imports = [ home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = specialArgs;
  };
};
```

Note: `homeModules.default` is **not** in `sharedModules`. Managed users get their home config
through [`myusers.nix`](./module-conventions.md)
(`home-manager.users.<name>.imports = [ configurations/home/<name>.nix ]`), so a host like test-vm
with an inline `test` user isn't forced to carry the full home config (which expects the home agenix
module).

### The hosts table

```nix
hosts = {
  ultraviolence = { };
  watchtower    = { };
  weyl          = { };
  guccimane     = { };
  shannon       = { };
  shimmer.system = "aarch64-linux";
  test-vm       = { };
};
```

`system` defaults to `x86_64-linux`; only `shimmer` (the DGX Spark) overrides it. See
[the fleet](./fleet.md) for what each host is.

### mkHost

```nix
mkHost = name: { system ? "x86_64-linux" }:
  nixpkgs.lib.nixosSystem {
    inherit specialArgs;
    modules = [
      { nixpkgs.hostPlatform = system; }
      homeManagerNixosModule
      ./nixos/${name}/default.nix
    ];
  };
```

Adding a NixOS host = one entry in `hosts` + a `configurations/nixos/<name>/`.

### Standalone home configs

```nix
homeUsers = lib.pipe (builtins.readDir ./home) [
  (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n))
  (lib.mapAttrs' (n: _: lib.nameValuePair (lib.removeSuffix ".nix" n) (./home + "/${n}")))
];
```

Every `configurations/home/<user>.nix` (currently `b7r6.nix`, `niteria.nix`) becomes a standalone
`homeConfiguration` for `nh home switch`. Adding one is auto-found — no registration needed.

### Outputs assembled here

```nix
flake = {
  nixosModules = {
    default   = ../modules/nixos;          # the gated everything-module
    dgx-spark = ../modules/nixos/dgx-spark;
    wayland   = ../modules/nixos/wayland;
  };
  homeModules.default = ../modules/home;
  nixosConfigurations = lib.mapAttrs mkHost hosts;
};

perSystem = { pkgs, ... }: {
  legacyPackages.homeConfigurations =
    lib.mapAttrs (_: mod: home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = specialArgs;
      modules = [ mod ];
    }) homeUsers;
};
```

## `modules/flake/default.nix` (the barrel)

This is the root flake-parts module. It constructs the `perSystem` `pkgs`, imports cross-cutting
modules, and imports every component subsystem.

### perSystem pkgs + overlays

```nix
_module.args.pkgs = import inputs.nixpkgs {
  inherit system;
  config = { allowUnfree = true; allowUnfreePredicate = _: true; };
  overlays = [
    self.overlays.default                       # the repo overlay
    inputs.devshell.overlays.default
    inputs.nix-vscode-extensions.overlays.default
    inputs.emacs-overlay.overlays.default        # emacs-pgtk -> 31.x
  ];
};
```

This single `pkgs` is what standalone `homeConfigurations`, devshells, and `packages` all use.
Applying the overlay here (rather than via `home-manager.nixpkgs.overlays`) avoids the
`useGlobalPkgs` warning. NixOS systems get the overlay through `modules/nixos/nix.nix` instead.

### Imports

The barrel imports cross-cutting modules and every component:

```nix
imports = [
  inputs.devshell.flakeModule
  ./fmt.nix
  ./overlays.nix
  ./devshell.nix
  ./docs.nix
  ./deploy.nix
  ./usb.nix
  ./themes
  ./attic
  ./backup
  ./coredns
  ./media
  ./nativelink
  ./registry
  ../../secrets        # secrets admin devShell + flake apps
];
```

### Component structure

Each subsystem is its own flake-parts module under `modules/flake/<name>/default.nix`. A component
owns its NixOS module (`nixos.nix`), checks (`checks/*.nix`), packages, and data. Components expose
`flake.flakeModules.<name>` as a graduation seam to standalone flakes.

```
modules/flake/
  default.nix            # the barrel (this file)
  fmt.nix                # treefmt
  overlays.nix           # self.overlays.default
  devshell.nix           # default devshell + agenix-shell
  docs.nix               # packages.docs + apps.docs-serve
  deploy.nix             # deploy-fleet app
  usb.nix                # USB installer images
  themes/                # fonts/stylix theme plumbing
  attic/default.nix      # attic component (NixOS module + check)
  backup/default.nix     # backup component (NixOS module + check)
  coredns/default.nix    # coredns component (NixOS module + VM test check)
  media/default.nix      # media component
  nativelink/default.nix # nativelink component (NixOS module + VM test check)
  registry/default.nix   # registry component (packages incl. coredns-zone)
```

### devShells / apps / checks / packages

- `devshells.default` imports `devshell.toml`; `devShells.secrets` comes from `secrets/` (agenix
  edit/rekey/rotate as `writeShellApplication`s + flake apps).
- `apps.build-usb` runs `scripts/build-usb.sh`; `apps.docs-serve` from `docs.nix`.
- `checks` (x86_64-linux only — `nixosTest` needs a Linux builder) — registered per-component:
  - `attic-cache` ← `modules/flake/attic/`
  - `backup-restic` ← `modules/flake/backup/`
  - `coredns` ← `modules/flake/coredns/default.nix` (VM test)
  - `nativelink` ← `modules/flake/nativelink/default.nix` (VM test)
  - `state-audit` ← `modules/flake/default.nix` (cross-cutting build check)
- `packages`:
  - `berkeley-mono` / `default` ← the Berkeley Mono font derivation
  - `ono-sendai-generator` ← `packages/ono-sendai-generator`
  - `state-audit` ← `packages/state-audit`
  - `gen-supabase-secrets` ← `packages/gen-supabase-secrets`
  - `coredns-zone` ← `modules/flake/registry/packages/coredns-zone/`
  - USB installer images via `nixos-generators`: `usb-{aarch64,x86_64}-{minimal,gnome}` (aarch64
    images pull in `self.nixosModules.dgx-spark`).

For module-level conventions inside `modules/nixos`, see
[module conventions](./module-conventions.md).
