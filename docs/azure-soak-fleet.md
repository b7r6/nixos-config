# NativeLink soak fleet on Azure — scope + build log (2026-10-13)

Status: **infra up, hosts installing** (see the log at the end). Decisions so far (2026-10-13):

- Soak the **OSS fork on NixOS VMs via the Dhall fleet** first; repeat the same
  soak against the enterprise Helm chart later so the two are differential.
- **Fresh resource group**, nothing shared with any pre-existing cluster in the subscription.
- Load = **rechaos gateway + chaos monkey + build loop**, running in-cluster.
- Code lives **in this repo**. Days-long runs; spot acceptable (see quota below).

## What already exists (surveyed)

| Thing | Where | Relevance |
| --- | --- | --- |
| Azure login (the operator's work subscription) | `az account show` | deploy identity; the user, not a service principal |
| A pre-existing AKS cluster with the vendor's Helm chart deployed | live, owned by colleagues | the later Helm leg of the differential; **not** touched by this work |
| The vendor's own cloud IaC | elsewhere | not used here |
| The Helm chart's Azure install path | vendor docs | the Helm leg, later |
| Dhall fleet (schema/render/fleet) | `modules/flake/nativelink/data/` | the topology program; today a single host (`shannon`) |
| Fork NixOS module | `inputs.nativelink-nix` → `nixos/module.nix` | renders `render-all.dhall` per `dhallHost`; `EnvironmentFile` only wired for R2 |
| Fork Azure Blob store | `nativelink-store/src/azure_blob_store.rs` | `provider: azure`; credential = **SAS URL or k8s workload identity only** (no VM managed identity) |
| Deploy path | `nix run .#deploy-fleet <host>…` | same-arch: build on shannon, `nix copy` over tailnet, register + background switch |
| Install path | `disko` input + `nixos-anywhere` (not an input; `nix run github:nix-community/nixos-anywhere`) | kexec install onto a stock Ubuntu VM |
| nixpkgs Azure modules | `virtualisation/azure-common.nix`, `azure-image.nix` | Hyper-V kernel modules; VHD fallback |
| Topology registry | `modules/flake/registry/data/hosts.dhall` | CoreDNS zone, OTel gateway lookup (`ch` tag → MagicDNS name) |
| rechaos | `~/src/b7r6/rechaos` (flake builds), `~/src/b7r6/rechaos-nativelink-raft` (harness: clean build → monkey → stress → verify → oracle) | the soak driver, REAPI-only, scrapes `/metrics` itself |

### Azure facts that shape the design

- **Spot quota is 3 vCPU** ("Total Regional Low-priority vCPUs") in westus2 and
  eastus2. Spot is unusable until a quota increase lands. Design keeps workers
  on their own hosts so they can move to spot later; v1 is on-demand.
- On-demand quota westus2: 200 regional vCPU (56 already in use), DSv5 65
  (24 used), DDSv5 65 (32 used), DADSv5 65, Dsv6/Ddsv6 350.
- D-series v5/v6 SKUs are restricted **zonally** (all three zones) but allowed
  as **regional (non-zonal)** VMs. Create VMs without `--zone`.
- No VNet exists outside the AKS node RG; the soak RG gets its own.

## Topology (v1)

Site `az` (westus2), four VMs, all x86_64 NixOS, all on the tailnet:

| Host (placeholder names) | SKU | Role | Dhall |
| --- | --- | --- | --- |
| `nl-az-a` | D8ds_v5 (8 vCPU / 32 GiB) | **scheduler** + CAS shard + worker | `isScheduler = True`, `casWeight = 4` |
| `nl-az-b` | D8ds_v5 | CAS shard + worker | `casWeight = 4` |
| `nl-az-c` | D8ds_v5 | CAS shard + worker | `casWeight = 4` |
| `nl-az-rig` | D4s_v5 (4 / 16) | rechaos gateway, monkey, workload, oracle; artifacts | not in the fleet |

- OS disk 256 GiB Premium SSD each; CAS fast tier + work dir on it (temp disk
  skipped for v1: it comes back blank after deallocate).
- **Slow tier = Azure Blob**, new storage account in the soak RG, container
  `nativelink-cas`, prefixes `cas/` + `ac/`, credential = container SAS in an
  agenix env file. Same object-store shape the chart uses, so the differential
  compares like with like. (R2 stays possible as a one-line switch.)
- `shannon` stays its own site (`sju1`, scheduler of one) and acts as a
  **client** of the Azure fleet over the tailnet; it is not in the Azure ring.
- Names in `fleet.dhall` use MagicDNS (`<host>.osiris-walleye.ts.net`) so no
  CoreDNS is needed on the VMs; registry entries + a DC code come after
  enrollment (tailnet IPs are only known then).
- Telemetry: the per-host OTel agent already ships to the host tagged `ch`
  (shannon) by MagicDNS name. Laptop-off gaps are acceptable because rechaos's
  own `/metrics` scraping drives the soak verdict.

Cheaper variant: D4ds_v5 for the three fleet nodes.

| Variant | Approx on-demand cost (westus2, Linux) |
| --- | --- |
| 3× D8ds_v5 + D4s_v5 + 4× 256 GiB P15 | ≈ $1.8/h ≈ $43/day |
| 3× D4ds_v5 + D4s_v5 + 4× 256 GiB P15 | ≈ $1.1/h ≈ $26/day |

Blob storage and in-region traffic are noise at this scale.

## Work items

### A. Infra script (az CLI, no Pulumi/Terraform)

`sh/azure-soak.sh` (or `nix run .#azure-soak -- up|install|deploy|down`):

1. `up`: RG `nl-soak-wus2`; VNet `10.42.0.0/16` with subnet `nodes` `/24` and a
   reserved `/20` for a later AKS leg; NSG allowing 22 only from shannon's
   current public IP; four VMs (`Canonical:ubuntu-24_04-lts:server:latest`,
   gen2, non-zonal, accelerated networking, temporary public IPs, ssh key);
   storage account (LRS, hot) + container; a 90-day container SAS written to
   the scratchpad for the agenix step.
2. `install`: per VM `nixos-anywhere --flake .#<host> --extra-files <hostkeys>
   root@<public-ip>` (kexec from Ubuntu). Host keys are pre-generated locally
   so agenix secrets (tailscale auth key, Azure env) decrypt on first boot.
3. `deploy`: `nix run .#deploy-fleet -- nl-az-a nl-az-b nl-az-c nl-az-rig`
   over the tailnet (same-arch path: build on shannon, copy, switch).
4. `lockdown`: drop the public IPs and the port-22 NSG rule once all four are
   on the tailnet.
5. `down`: `az group delete`; hosts flip to `enabled = False` in the Dhall.

Fallback if kexec misbehaves on Azure: build a VHD with `nixos-generators -f
azure` (already an input), upload, create VMs from it.

### B. nixos-config changes

| File | Change |
| --- | --- |
| `configurations/default.nix` | add the four hosts (x86_64 default) |
| `configurations/nixos/nl-az-{a,b,c,rig}/` | `default.nix`, `configuration.nix`, `disko.nix` (GPT: 1 GiB ESP + ext4 root) |
| `modules/nixos/azure.nix` (new, gated) | imports `azure-common.nix`; serial console; swapfile; `tailscale.acceptDNS = true`; no NVIDIA/desktop; firewall default |
| `modules/flake/nativelink/data/fleet.dhall` | `HostDef.site : Text`; per-site scheduler + ring (`enabledHosts` filtered by site); the three az hosts; `slowTier` switch `r2 \| azure` |
| `modules/flake/nativelink/data/render.dhall` | `azure` backend constructor emitting `experimental_cloud_object_store { provider: "azure", sas_url: "${AZURE_CAS_SAS_URL}" }` |
| `modules/flake/nativelink/shim.nix` | when the host's site is azure, append `/run/agenix/nativelink-azure-env` to the service's `EnvironmentFile` (the fork module only wires R2's) |
| `secrets/keys.nix` + `agenix -r` | the four pre-generated host keys |
| `secrets/secrets.nix` | `nativelink-azure-env.age` (`AZURE_CAS_SAS_URL=…`), scoped to the az hosts |
| `modules/flake/registry/data/hosts.dhall` | zone for the Azure site + four hosts (after enrollment; tailnet IPs) |
| `flake.nix` | `rechaos` input (public `b7r6/rechaos`) for the rig |
| `docs/` | runbook + `todo-frontier` entry |

The `configurations/nixos/<host>-bootstrap` two-step is not needed: the VMs
never build anything, they receive closures from shannon.

### C. The rig

- `rechaos-gateway.service`: `rechaos serve --upstream-host nl-az-a.<magicdns>
  --upstream-port 50051 --port 50070 --record /var/lib/soak/<run>/gateway/…`.
- `soak-run.service` + timer: an adaptation of `rechaos-nativelink-raft/run.sh`
  for remote targets. Phases: clean REAPI build through the gateway →
  `chaos-monkey.py --execution --soak` for N hours (seeded) → scheduler stress →
  verify build → `rechaos oracle`. Process chaos (`restart-chaos.sh`) becomes
  `ssh nl-az-a systemctl kill -s KILL nativelink` on a seeded schedule, since
  `process_chaos.py` is local-only by design.
- Artifacts under `/var/lib/soak/runs/<utc>/` (manifest, summary, findings,
  timelines, trees); shipped off-box by the existing restic → R2 backup module.
- The chaos monkey needs the rechaos dev-shell Python (grpcio + generated
  protos). Either package `scripts/` as a flake app in rechaos (small PR there)
  or run it via `nix develop` on the rig; decide at implementation.

### D. Workload

- **v1**: `rechaos-nativelink-raft/workload/reapi_workload.py` (synthetic REAPI
  actions, deterministic trees for the oracle) plus a genrule-level Bazel demo.
  Workers advertise `container-image = ""`, so only toolchain-free actions run.
- **v2**: a real Bazel target through LRE. NixOS workers can carry the LRE
  toolchain closure in their system closure (`system.extraDependencies`), which
  makes `/nix/store`-path toolchains hermetic without an image pull. Candidate
  target: a NativeLink subset, or the straylight-prelude examples.

## Acceptance for a run

1. All three workers register with the scheduler (admin API / metrics).
2. Clean build → verify build: `rechaos oracle` says `equivalent`.
3. Monkey `--execution --soak` ≥ 24 h: zero findings, or every finding triaged
   to a frozen reproducer; no rising floor on RSS / fds / queue depth.
4. Scheduler `kill -9` recovers within `workerTimeoutS`; workers reconnect;
   no stuck `queued` actions after drain.
5. Azure Blob error rate and `cas-slow` latency recorded for the differential.

## Differential leg (later)

Same rig, same seeds and policies, pointed at the Helm chart: either a fresh
AKS in the reserved `/20` of the soak VNet, or the existing cluster via an internal
LoadBalancer on the CAS Service. Compare `summary.json`, oracle verdicts, and
the recorded metrics side by side.

## Risks and unknowns

- `nixos-anywhere` kexec on Azure gen2 Ubuntu is commonly used but untested
  here; VHD fallback exists.
- The SAS token expires; rotate via the agenix secret. VM managed identity is
  not supported by the fork's Azure store today (workload identity only).
- The fork's config renderer has no Azure constructor yet; it is additive.
- The always-on module set (sddm etc.) must be headless-safe; watchtower ran
  it as a server, so it should be. Verify on the first VM.
- First deploy copies the full system closure to four hosts over the tailnet
  from a laptop; expect several GB per host.
- Spot needs a quota request (3 → ≥ 64 vCPU) before any worker can be spot.

## Open decisions

1. Host names and the DC code for the Azure zone in the registry (naming scheme
   says nearest Equinix; westus2 → Seattle `se2`?).
2. Slow tier: Azure Blob via SAS (recommended for the differential) or R2.
3. Fleet node size: D8ds_v5 (≈ $43/day) or D4ds_v5 (≈ $26/day).
4. File the spot quota request now, in parallel?
5. v2 Bazel target for the LRE workload.

## Build log (2026-10-13)

- `sh/azure-soak.sh up` created rg `nl-soak-wus2`: vnet 10.42.0.0/16, NSG (22 from the
  builder's public IP only), four regional VMs (3× D8s_v5 + D4s_v5, 256/128 GiB Premium OS
  disks, `--security-type Standard`), storage account `nlsoakcas1000` + container
  `nativelink-cas`, a 120-day container SAS → `nativelink-azure-env.age`.
- Host keys pre-generated on the builder and shipped with `nixos-anywhere --extra-files`
  (the rig also gets its soak ssh key at /var/lib/soak/id_ed25519); all secrets rekeyed.
- `mkHost` did not accept `bootstrap = false` (latent since the flag landed; test-vm was
  never evaluated). Fixed by accepting the argument.
- `EDITOR="cp …" agenix -e` silently wrote an EMPTY secret. The SAS env was encrypted with
  plain `age -e -R <recipients>` instead (admin keys + the three node host keys).
- The az SKUs (D*v5/v6) are zone-restricted for this subscription; regional VMs work.
- **The builder's uplink is a laptop on Wi-Fi: ~300 KB/s.** `nix copy` only crawls for
  paths absent from public caches; everything else the VM substitutes from
  cache.nixos.org at 160 MB/s. The first attempt shipped 40 GiB per host because the
  registry imports every user's desktop home-manager config (36.6 GiB, incl. uncached
  cursor / VS Code extensions / fonts). `hyper-modern-nixos.identity.homeManager = false`
  on the Azure module brings a node to 8.6 GiB, of which ~142 MiB is uncached (the static
  NativeLink binary, the initrd, hwdb). Minutes per host.
- Store layout on the VM: a single OS disk at /dev/sda (D*s_v5 has no temp disk), ESP +
  ext4 root via disko.

- 2026-10-14: the site lives on its OWN tailnet (`tail8ec1af.ts.net`, a fresh tailnet under the
  dedicated `deus-ex-b7r6` GitHub identity; policy + charter in hypermodern-nativelink `netops/`).
  The old fleet auth key and the netrc API token were both dead; the new key is the site's own
  agenix secret. `azure-soak.sh enroll` joined the four hosts; the ring formed on MagicDNS; the
  first `soak build` ran 21 actions on the workers through the rechaos gateway with 0 findings.
  shannon is not on that tailnet: `azure-soak.sh deploy` reaches nodes via ProxyJump through the
  rig, which stays the public-IP bastion after `lockdown`.

- **Lockdown lesson (2026-10-14 03:31Z):** removing the nodes' public IPs cut ALL their egress —
  Azure retired default outbound access for new VNets (2025-09), so without a public IP or a
  NAT gateway a VM cannot reach the Tailscale control plane or Blob. Fixed with one NAT gateway
  on the subnet (`nl-soak-nat`, 20.3.208.140); `up` now creates it and `lockdown` refuses to
  run without it. Campaign 1 (03:30Z) overlapped the outage and is contaminated; rerun.
- Tags live: `tag:nl-soak` on a/b/c, `tag:nl-rig` on the rig (`azure-soak.sh tag`); the policy
  in hypermodern-nativelink `netops/` is enforced (ring + worker_api + bastion verified).

## Follow-ups

- Dhall `site`/`slowTier` landed in `fleet.dhall`; shannon's render is unchanged.
- The standalone flake is being built at `~/src/hypermodern/hypermodern-nativelink-0x01`
  (Dhall library + modules + soak rig + telemetry contract + Grafana dashboard); nixos-config
  swaps its path import for the input once the first campaign has run.
- Spot: quota ticket for Low-priority vCPUs (3 → ≥64) before any worker pool can be spot.

## Sites (2026-10-14)

More than one cluster, each soaking a different NativeLink rev, from ONE typed list. The
mechanism, then the second site, then the lessons.

### The source of truth

`examples/sites.dhall` in hypermodern-nativelink (typed by `dhall/site.dhall`): per site its
Azure footprint (region, resource group, VNet + subnet, NSG, NAT gateway, storage account +
container), tailnet suffix and its two tags, nodes (size, OS disk, `casWeight`, `casFastBytes`,
`maxInflightTasks`, which one schedules), rig and builder sizes, `nativelinkRev` (a nixos-config
flake-input name + the commit it must be locked to), that rev's config `dialect`
(`fork` | `upstream`), and its secret names (`casEnvSecret`, `tailscaleAuthKeySecret`). The az
site is in it exactly as deployed (weights 4/4/4, 100 GiB fast tier, 8 in flight, `nl-az-a`
schedules). Everything else derives:

| consumer | derives |
| --- | --- |
| `examples/fleet.dhall` | a `HostDef` per node (`List/concatMap` over the sites; site identity by index, Dhall has no `Text` equality); the ring and scheduler per site |
| `netops/policy.dhall` → `nix run .#render-policy -- --write` | `netops/tailscale-policy.hujson`: per-site tags, the three rules, tests, plus a deny test per ordered pair of sites |
| `nix run .#render-sites -- [sites.dhall] [site]` | the JSON `sh/azure-soak.sh --site <s>` reads every name and size from |
| `configurations/sites.nix` | a `nixosConfiguration` per node, rig and builder of every site (IFD), on `configurations/nixos/nl-site/` |
| the flake's `secrets/secrets.nix` | `agenix/<casEnvSecret>.age` scoped to that site's nodes; `agenix/hostkeys/<host>.age` per keys.nix host |

Proofs: the fork-dialect render of the pre-existing hosts is byte-identical before and after
(render-all → `jq -S` → sha256 `0222538c1ac620ca0e057f8c4e70c8aa21dc13131a26f0243f47023ee8b38587`;
nl-az-a `b0aac17b…`, nl-az-b/c `53f0d5e7…`, shannon `5d6a2072…`); the generated policy's az
subset (tag owners, rules, tests) equals the hand-written file parsed as JSON; `nix flake check`
carries `fleet-example`, `sites-example` and `policy-rendered`.

### The dialect

Upstream NativeLink rejects unknown config keys and has none of the fork's `nix_cache`,
`oci_registry`, `fetch.oci`, `cas_witness` or `experimental_prometheus`. A site's `dialect`
decides what `fleet.dhall` emits: `fork` is everything; `upstream` is the common subset (ring,
scheduler, `worker_api`, the Azure slow tier via `sas_url`, `cache_metrics`, `slow_direction`,
`max_inflight_tasks`, the worker `entrypoint` the module injects) with no OCI service and no
Prometheus listener, and the CAS/AC `fast_slow` WRITES THROUGH to the slow tier. That last one
is a real behavioral difference, found on az2's first smoke build (16/16 `FAILED_PRECONDITION`,
"Execute pre-check found missing CAS blobs"): upstream's `FastSlowStore::has_with_results`
asks the slow store first, so with the fork-era `slow_direction: get` (nothing ever written to
Blob) every input the client had just uploaded read as missing. The fork's `has()` is
fast-first, one of the fixes az soaks, which is why az runs fine on a read-only tier.
Verified by running the az2 render through the 1.7.7 binary on the operator's box: it
deserializes, instantiates every store and dials its ring (then fails to bind 50052, which the
laptop's own NativeLink holds). Consequence: an
upstream-dialect node serves no `/metrics`; the rig's worker-count probe is best-effort and the
OTel scrape of 50051/50052 is empty there (OTLP push still carries the metrics).

### Multi-rev

One flake input per rev under soak, `nativelink-rev-<short>` in `flake.nix`; the site names it
in `nativelinkRev.input` and `configurations/sites.nix` sets
`hyper-modern-nixos.nativelink.package` from it, asserting `inputs.<name>.rev` equals the
site's `rev` (a drifted lock refuses to evaluate). The NixOS module is always the fork's
(`nativelink-nix`): it only execs `nativelink <json>`. To add a rev: one input line, one
`nativelinkRev` (+ `dialect`) in the site, `nix flake lock`.

- az: `nativelink-nix`, fork integration branch `7eba9bf` (pre-fix).
- az2: `nativelink-rev-1-7-7`, upstream `TraceMachina/nativelink` `b1ca26e08296f50935136b2385873354c88286ed`
  (head of the "Release NativeLink v1.7.7" PR #2937, open at the time), upstream dialect, its
  own nixpkgs pins so it builds as upstream's CI does. The from-source build took ~25 minutes on
  the laptop (crate deps substituted).

### The script

`sh/azure-soak.sh --site <s> …` (or `AZS_SITE`); nothing is hard-coded. Every subcommand kept;
new: `keys` (what `up` runs: generate a host's ed25519 key before the VM exists, land the
private half in the flake's `agenix/hostkeys/<host>.age` encrypted to the operators, append the
public half under the `# ── sites …` marker of BOTH `secrets/keys.nix`, rekey both trees; the
rig also gets its soak root key, public half at the flake's `secrets/pub/<rig>-soak-root.pub`),
`install` (decrypts those to a mode-0700 scratch dir for `--extra-files`), `sas --put` (lands
the site's CAS env through put-secret), `builder up|down|rm|status|line`. The az host keys that
lived only in a session scratch directory are now in the tree too.

A third site, end to end:

```sh
# hypermodern-nativelink: one record in examples/sites.dhall (fresh names, tag pair, storage
# account, address space), one casEnvSecret rule in secrets/secrets.nix, then
nix run .#render-policy -- --write        # paste netops/tailscale-policy.hujson into the console
nix flake check && git commit && git push
# nixos-config: one input line in flake.nix if the rev is new; nix flake lock; then
sh/azure-soak.sh --site az3 up            # RG, net, NAT, VMs, storage, host keys landed + rekeyed
sh/azure-soak.sh --site az3 sas --put
nix flake lock --update-input hypermodern-nativelink   # while the input is a path: (see lessons)
sh/azure-soak.sh --site az3 install       # four nixos-anywhere runs
sh/azure-soak.sh --site az3 policy push   # the generated policy, validated, then live
sh/azure-soak.sh --site az3 tskey         # tagged enrollment keys, landed in the flake
sh/azure-soak.sh --site az3 devices       # hosts enroll tagged at first boot; verify
ssh … nl-az3-rig 'soak status; soak build smoke'
sh/azure-soak.sh --site az3 lockdown
```

### Lessons

- **eastus2 had no D\*s_v5 capacity** for this subscription (every v4/v5 8-vCPU size failed
  preflight with `SkuNotAvailable: Capacity Restrictions`); `Standard_D8s_v6` / `D4s_v6` /
  `D16s_v6` validate (Dsv6 quota 350). az2 runs on v6, one line per machine in the site. The
  az CLI's own error handler crashes on this preflight error (`The content for this response was
  already consumed`); `az vm create … --validate` shows the real inner error.
- **v6 = NVMe behind Hyper-V PCI.** D\*s_v6 presents the OS disk as `/dev/nvme0n1` ("MSFT NVMe
  Accelerator", on a passthrough bus `pci-c05b:…`), not `/dev/sda`: disko's device is now chosen
  by the host's size, and the v6 initrd force-loads `pci_hyperv` + `nvme` — with `nvme` merely
  available, stage 1 waited 90 s for `/dev/disk/by-partlabel/nixos` and dropped to emergency
  (serial log via `az vm boot-diagnostics enable` + `get-boot-log`, which returns one
  JSON-escaped string). Four installed-but-unbootable VMs were recreated; the fix is in nl-site.
- **Never edit `sh/azure-soak.sh` while an instance runs:** bash reads the file as it goes, and
  two installs died mid-run with "line N: … Is a directory" after an edit. Run long subcommands
  from a copy (`cp sh/azure-soak.sh "$scratch"/ && bash "$scratch"/azure-soak.sh …`).
- **A `path:` input is a snapshot.** nixos-config takes hypermodern-nativelink as `path:`; every
  change there (a landed secret, a new `secrets/pub` file, a site edit) needs
  `nix flake lock --update-input hypermodern-nativelink` before nixos-config sees it, or a host
  evaluates against a stale tree (an az2 node built before its CAS env was landed would have
  no `age.secrets` entry for it). The input becomes the git URL once the repo is public or a
  deploy key exists.
- **The policy is pushed, not pasted:** `azure-soak.sh --site <s> policy validate|push` runs the
  generated file's tests server-side and pushes it with `If-Match` on the live etag (a concurrent
  console edit is refused, not overwritten); the API token is the flake's operators-only
  `agenix/tailscale-api-token.age`. `tskey` mints a site's TAGGED enrollment keys (one per role,
  reusable, pre-authorized) so hosts enroll already tagged: no untagged window, no `tag` step.
  The az site predates this and still enrolls with the untagged shared key + `tag`.
- **The install uplink is the bound**, not the build: four parallel nixos-anywhere runs share
  the laptop's 300 KB/s for the uncached paths (the NativeLink binary ×3, an initrd each). The
  builder (`builder up`) is the fix: a D16s_v6 in the site's VNet, NixOS via the same wrapper
  (role `builder`), host key pinned in the `--builders` line it prints; `AZS_BUILDERS=… deploy`
  builds there. Its copy leg (closures leaving from the builder rather than the laptop) is the
  documented follow-up below.

### Fold-in of az (TODO[b7r6])

az stays on `configurations/nixos/nl-az/` (lane 1's observability work landed there during
this session). To fold it onto `nl-site`: drop `"az"` from `handWritten` in
`configurations/sites.nix`, delete `configurations/nixos/nl-az-{a,b,c,rig}/` and the hosts'
`default.nix` entries, move `nl-az/rig.nix` to `nl-site/rig-sink.nix` (nl-site already imports
it by path), copy `nl-az/rig-root-key.pub` to the flake's `secrets/pub/nl-az-rig-soak-root.pub`
(the same key, already landed as `agenix/hostkeys/nl-az-rig-soak-root.age`), and prove
`nix eval .#nixosConfigurations.nl-az-{a,b,c,rig}.config.system.build.toplevel.drvPath` is
byte-identical before and after. Expect two deliberate differences to reconcile first: the
fleet dir (nl-az renders nixos-config's `modules/flake/nativelink/data`, nl-site renders the
flake's `examples/`; the JSON is identical, the store path is not) and `expectedWorkers` on the
rig (nl-site sets it from the node count). Never during a campaign
(`systemctl list-units 'soak-*'` on nl-az-rig).
