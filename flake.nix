{
  description = "// hypermodern // nixos";

  # The build must be self-sufficient from PUBLIC caches — never dependent on a
  # private/self-hosted one. The fleet's nativelink nix_cache (127.0.0.1:50071)
  # is a pure OPTIONAL accelerator: it lives only in the b7r6 user nix.conf, is
  # fail-open (a dead endpoint falls through to source), and is deliberately NOT
  # listed here, so it is never assumed by a root build such as `disko-install`.
  #
  # What IS listed are the public substituters the stock installer ISO does not
  # know about on its own (it ships only cache.nixos.org). Without this block a
  # fresh `disko-install` rebuilds the entire nix-community + supabase-postgres
  # closure from source for no reason. `disko-install`/`nix` honor these with
  # --accept-flake-config (root on the ISO is trusted). The fork packages
  # (b7r6/nativelink, narsil, wintermute, coredns-zone, …) have no public cache
  # and still build from source — that is accepted, not a failure.
  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://nix-postgres-artifacts.s3.amazonaws.com"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nix-postgres-artifacts:dGZlQOvKcNEjvT7QEeBMKja1bMnGqCiQ5vzg4IZ4Qbk="
    ];
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = [
        ./modules/flake
        ./configurations
      ];
    };

  inputs = {
    # nixpkgs: the sensenet-ai fork at HEAD (NOT upstream nixpkgs-unstable). The
    # whole tree rides this via `follows = "nixpkgs"`; pin anything we touch to it.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default-linux";

    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";

    agenix-shell.url = "github:aciceri/agenix-shell";
    agenix-shell.inputs.nixpkgs.follows = "nixpkgs";

    # ORBITAL // FORGE: the native Haskell read boundary in the web monorepo.
    # Watchtower runs its Forgejo adapter beside the upstream and nginx exposes
    # only the stable /orbital-forge/api/ path over the tailnet.
    orbital-forge.url = "github:hypermodern-src/orbital-straylight-www?dir=projects/orbital-forge";
    orbital-forge.inputs.nixpkgs.follows = "nixpkgs";

    # wintermute: the hot-reload theme reconciler as its own production
    # (extracted 2026-10-07 from the continuity monorepo's
    # b7r6/wintermute-0x01 branch, proof-carrying dep cone included).
    # Deliberately does NOT follow our nixpkgs: it pins its own lean4-nix
    # toolchain and should build exactly as its own CI builds it.
    wintermute.url = "github:b7r6/wintermute";

    # straylight-nvidia-sdk: modern nv. Pulled for wintermute-field — the
    # wallpaper field as a CUDA kernel, and the zero-copy wayland presenter
    # daemon (kernel writes the compositor's wl_shm pool over GB10 coherent
    # memory). Like continuity, deliberately does NOT follow our nixpkgs.
    # GitHub mirror, same reason as continuity.
    straylight-nvidia-sdk.url = "github:hypermodern-src/orbital-straylight-nvidia-sdk";

    # narsil: HM type checker / linter / LSP for Nix + embedded bash
    # (b7r6's own; holds 99.92% of nixpkgs). Like continuity, deliberately
    # does NOT follow our nixpkgs — it pins its own Haskell toolchain.
    narsil.url = "github:b7r6/narsil";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # The jetson (filament) rides proven pins, not the fleet nixpkgs: jetpack
    # HEAD (L4T 39.x) wants CUDA 13.2 manifests and the proven rev wants
    # 13.0.3 — neither exists in the sensenet-ai fork's cuda-modules. This
    # pair is exactly the closure verified on hardware 2026-08-06; bump both
    # together, deliberately.
    nixpkgs-jetson.url = "github:NixOS/nixpkgs/af84f9d270d404c17699522fab95bbf928a2d92f";
    jetpack-nixos.url = "github:anduril/jetpack-nixos/55bcdf742a957748a759e5eaf69b86ad9d779330";
    jetpack-nixos.inputs.nixpkgs.follows = "nixpkgs-jetson";

    impermanence.url = "github:nix-community/impermanence";

    impurity.url = "github:outfoxxed/impurity.nix";

    # Hyprland 0.53.0 with matching hy3 hl0.53.0.1
    # (hy3 hasn't caught up to 0.54.0 yet)
    # hyprland.url = "github:hyprwm/Hyprland?ref=v0.53.0&submodules=1";

    # hy3.url = "github:outfoxxed/hy3?ref=hl0.53.0.1";
    # hy3.inputs.hyprland.follows = "hyprland";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    nvf.url = "github:NotAShelf/nvf";
    nvf.inputs.nixpkgs.follows = "nixpkgs";
    nvf.inputs.flake-parts.follows = "flake-parts";

    nix4nvchad.url = "github:nix-community/nix4nvchad";
    nix4nvchad.inputs.nixpkgs.follows = "nixpkgs";

    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    xremap-flake.url = "github:xremap/nix-flake?ref=master";
    xremap-flake.inputs.nixpkgs.follows = "nixpkgs";

    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    # Vendored Codex CLI, exposed as `nix run .#codex` and installed by
    # modules/home/llm. Keep the vendor's nixpkgs and Rust toolchain pins so
    # its existing builds remain reusable. Update with `nix flake update codex`.
    codex.url = "github:hypermodern-src/orbital-vendor-codex";

    # opencode — the Anomaly fork (github:anomalyco/opencode, default branch
    # `dev`). Its overlay (opencode.overlays.default) provides pkgs.opencode +
    # pkgs.opencode-desktop, wired into the fleet overlays (pkgs.nix + nixos/nix.nix)
    # and installed for the b7r6 home via modules/home/llm. `nix flake update
    # opencode` bumps to the newest fork commit. Its own nixpkgs is unstable; we
    # pin it to ours per the repo-wide convention.
    opencode.url = "github:anomalyco/opencode";
    opencode.inputs.nixpkgs.follows = "nixpkgs";

    # Bleeding-edge Emacs (master/31.x pgtk) + same-day MELPA snapshots. nixpkgs
    # only ships emacs 30.2; the overlay exposes pkgs.emacs-pgtk tracking the
    # emacs-31 dev branch. Consumed by modules/home/emacs to drive
    # mkHypermodernEmacs at 31. NOTE: ghostel's native module is rebuilt against
    # whatever emacs this resolves to, so a 31 bump recompiles ghostel-module.so.
    emacs-overlay.url = "github:nix-community/emacs-overlay";
    emacs-overlay.inputs.nixpkgs.follows = "nixpkgs";

    # NativeLink remote-execution (Bazel/Buck2 RE). Provides the `nativelink`
    # binary for x86_64-linux and aarch64-linux; there is NO upstream NixOS
    # module, so modules/nixos/common/nativelink.nix hand-rolls the service.
    # Off by default; building from source is heavy unless you add
    # nativelink.cachix.org to substituters.
    # Pinned to b7r6's integration branch: straylight fork + all upstream-bound
    # fix branches (shard-ring failover, CAS integrity, scheduler-redis, etc.).
    nativelink.url = "github:b7r6/nativelink?ref=integration/straylight-plus-all-fixes-2026-10-05";
    nativelink.inputs.nixpkgs.follows = "nixpkgs";

    # Straylight's NativeLink fork carrying the Nix binary-cache (substituter)
    # service — `nix_cache` — that upstream lacks. Consumed by the `nixCache`
    # option in modules/flake/nativelink to serve the Nix HTTP binary-cache
    # protocol. It is a strict superset of upstream, kept as a SEPARATE input so
    # standing up the Nix cache on one host does not rebuild the RE fleet's
    # `nativelink`. Moved off the self-hosted forge (watchtower retired
    # 2026-10-07) onto the GitHub fork; the integration branch is a superset
    # of migrate-1.7.3.
    nativelink-nix.url = "github:b7r6/nativelink?ref=integration/straylight-plus-all-fixes-2026-10-05";
    nativelink-nix.inputs.nixpkgs.follows = "nixpkgs";

    # ── NativeLink revs under soak (docs/azure-soak-fleet.md, "Sites") ──────────
    # One input per rev a site soaks, named `nativelink-rev-<short>`; a site in
    # hypermodern-nativelink's sites.dhall names its rev by this input name
    # (`nativelinkRev.input`) and the site consumer (configurations/sites.nix)
    # sets `hyper-modern-nixos.nativelink.package` from it, asserting the
    # locked rev is the one the site says. The NixOS MODULE always comes from
    # `nativelink-nix` (the fork; it only execs `nativelink <json>`); the
    # Dhall render follows the site's `dialect` (fork | upstream) so an
    # upstream binary never sees a fork-only config key. The az site itself is
    # `nativelink-nix` (7eba9bf, the fork's integration branch: pre-fix).
    #
    # To add a rev: one input line here + `nativelinkRev` in the site +
    # `nix flake lock` (the lock gains one node; nothing else moves).
    #
    # 1.7.7: UPSTREAM main at the head of "Release NativeLink v1.7.7" (PR
    # #2937), the post-fix side of the scheduler-race differential az2 soaks
    # against az. Deliberately does NOT follow our nixpkgs: it builds exactly
    # as upstream's CI builds it (musl static via its own pins).
    nativelink-rev-1-7-7.url = "github:TraceMachina/nativelink/b1ca26e08296f50935136b2385873354c88286ed";

    # 1.7.6: UPSTREAM tag v1.7.6, the pure PRE-fix side of the differential
    # (az soaks it since 2026-10-14 ~15:00Z; before that az ran the fork's
    # integration branch, which is no longer on the wall). Same `upstream`
    # dialect as 1.7.7, so the only difference between the two sites is the
    # binary. Its config surface was checked against 1.7.7's at the tag:
    # 1.7.7 adds `reservation_hold`, `executing_sweep_interval_s`, the
    # `throttle_retry_*` object-store knobs and `forward_headers`; everything
    # the upstream render emits exists at both. Own nixpkgs pins, as 1.7.7.
    nativelink-rev-1-7-6.url = "github:TraceMachina/nativelink/be96a8a0cf38b74d0997b48ee45a1ec8c6a6e925";

    # rechaos — the black-box REAPI chaos + determinism gateway that drives the
    # Azure soak rig (modules/flake/nativelink/soak). Pinned by REV on purpose:
    # the repo lands hot while a soak runs, and a soak's rechaos must not move
    # under it. Bump deliberately (`nix flake update rechaos`) between runs;
    # the run manifest records the rev. Own nixpkgs (Haskell package set).
    rechaos.url = "github:b7r6/rechaos/7c90b91b2755d2e2fbb8804664bc0921acd4b38a";

    # hypermodern-nativelink — the Dhall-native NativeLink flake being split out
    # of modules/flake/nativelink (typed fleet, modules, soak rig, telemetry,
    # and the Azure site's OWN agenix secrets: tailnet key + CAS SAS). Local
    # checkout only until it is pushed; then github:b7r6/hypermodern-nativelink.
    # `git+file` with a ref locks a COMMIT. A `path:` input locks the whole
    # directory's NAR hash: uncommitted edits, .direnv/, result and .ruff_cache
    # included. So any edit or direnv reload there broke every build here with
    # "NAR hash mismatch". Commit in the checkout, then
    # `nix flake update hypermodern-nativelink`.
    hypermodern-nativelink.url = "git+file:///home/b7r6/src/hypermodern/hypermodern-nativelink-0x01?ref=main";
    hypermodern-nativelink.inputs.nixpkgs.follows = "nixpkgs";
    hypermodern-nativelink.inputs.nativelink.follows = "nativelink-nix";
    hypermodern-nativelink.inputs.rechaos.follows = "rechaos";

    # rayfish — our vendored fork of the iroh-powered P2P mesh VPN (rayfish/rayfish),
    # remapped off Tailscale's 100.64.0.0/10 CGNAT block onto 10.64.0.0/10 so it
    # coexists with the tailnet as an INDEPENDENT fallback mesh (out-of-band reach
    # for boxes with no IPMI when the tailnet/control-plane is down). Its own flake
    # exposes packages.rayfish (the `ray` daemon+CLI). Consumed by
    # modules/nixos/rayfish.nix. Fetched over the self-hosted forge's HTTPS endpoint.
    rayfish.url = "github:hypermodern-src/orbital-vendor-rayfish?ref=master";
    rayfish.inputs.nixpkgs.follows = "nixpkgs";

    # attic binary cache — our fork (sensenet-ai) carrying the configurable
    # NAR chunk-prefetch fix (chunking.nar-prefetch). Upstream hardcodes prefetch
    # depth 2, which serializes chunk GETs against R2 (~150ms each) and makes
    # cold multi-GB pulls crawl. Its overlay (attic.overlays.default) provides the
    # patched pkgs.attic-server consumed by modules/nixos/attic.nix.
    # See docs/src/architecture/attic-prefetch.md.
    attic.url = "github:sensenet-ai/attic/b7r6/nar-prefetch-concurrency";
    attic.inputs.nixpkgs.follows = "nixpkgs";

    # vLLM serving harness for Qwen3.6-27B-NVFP4-MTP on Blackwell. Provides
    # nixosModules.vllm (managed systemd service) + gpuPowercap (475W cap).
    # It pulls nvidia-sdk for the NGC-extracted python environment (torch cu130,
    # triton, tensorrt_llm) and does NOT follow our nixpkgs fork, so the NGC
    # packages stay pinned to upstream nixos-unstable.
    vllm-stack.url = "github:hypermodern-src/orbital-hypermodern-vllm";

    # Transitive forge refs, overridden onto mirrors (the forge retired with
    # watchtower 2026-10-07): vllm-stack's `nvidia-sdk` is the same repo as
    # straylight-nvidia-sdk under its pre-rename name.
    vllm-stack.inputs.nvidia-sdk.url = "github:hypermodern-src/orbital-straylight-nvidia-sdk";
    vllm-stack.inputs.nvidia-sdk.inputs.modern-nix.follows = "straylight-nvidia-sdk/modern-nix";
    straylight-nvidia-sdk.inputs.modern-nix.url = "github:hypermodern-src/orbital-straylight-modern.nix";

    # Self-hosted Supabase. NOT a flake — we consume its docker/ tree as a SOURCE
    # for the version-coupled config files (volumes/api/kong.yml, the db init
    # SQL, volumes/pooler/pooler.exs) that ship OUTSIDE the container images and
    # are pinned in lockstep with the image tags in modules/nixos/supabase. There
    # is no upstream NixOS module (native support is on their roadmap; this is the
    # community-contribution shape until then). flake = false so it's a plain
    # content-addressed checkout, never evaluated.
    supabase.url = "github:supabase/supabase";
    supabase.flake = false;

    # Supabase's Postgres: Postgres 17 + 112 extensions (pg_graphql, pgsodium,
    # pg_net, pg_jsonschema, pgjwt, pgvector, …) as a NATIVE Nix derivation with
    # a binary substituter (nix-postgres-artifacts.s3.amazonaws.com). This is what
    # runs INSIDE supabase/postgres Docker images — already Nix-built, just wearing
    # a container costume. We consume the package directly via
    # services.postgresql.package, killing the DB container entirely.
    # supabase-postgres: NOT following our nixpkgs. Their S3 binary cache only
    # has artifacts for their pin. Build with --accept-flake-config or add their
    # substituter to nix.conf to get cache hits.
    supabase-postgres.url = "github:supabase/postgres";
  };
}
