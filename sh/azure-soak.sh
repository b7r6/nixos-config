#!/usr/bin/env bash
# azure-soak — infra for the NativeLink soak SITES (docs/azure-soak-fleet.md, "Sites").
#
# Plain `az` CLI. Nothing here is hard-coded to a site: every name, size, region
# and secret comes from hypermodern-nativelink's sites.dhall through its
# `render-sites` app, so a second site is one Dhall record. Run from the
# operator's box with `az login` done.
#
#   azure-soak --site <s> up                 RG, VNet/NSG/NAT, the site's VMs, storage + container,
#                                            host keys generated + landed (see `keys`)
#   azure-soak --site <s> keys [host...]     generate a host's ed25519 key (and the rig's soak root key),
#                                            land the private halves in the site flake's agenix tree
#                                            (operators only), list the public halves in BOTH keys.nix,
#                                            rekey both trees. Idempotent; `up` runs it.
#   azure-soak --site <s> ips                public/private IPs of the VMs
#   azure-soak --site <s> install [host...]  nixos-anywhere each VM (default: nodes + rig); the host
#                                            keys are decrypted to a scratch dir for --extra-files
#   azure-soak --site <s> sas [--put]        print AZURE_CAS_SAS_URL=… ; --put lands it in the site's
#                                            CAS env secret (sites.dhall casEnvSecret) via put-secret
#   azure-soak --site <s> enroll [host...]   tailscale up on hosts stuck in NeedsLogin, with the site's
#                                            auth key (env TS_AUTHKEY, or the site flake's secret)
#   azure-soak --site <s> tag [host...]      advertise the site's tags on enrolled hosts
#   azure-soak --site <s> lockdown           nodes lose their public IPs; the rig stays the ssh bastion
#   azure-soak --site <s> deploy [host...]   build here, copy + switch (nodes via ProxyJump through the rig)
#   azure-soak --site <s> status             what exists
#   azure-soak --site <s> down               delete the resource group (everything)
#   azure-soak --site <s> builder up|down|rm|status|line
#                                            the site's builder VM (D16s_v5): create + install (up),
#                                            deallocate when idle (down), delete (rm), and `line`
#                                            prints the nix `--builders` spec for the laptop
#
# Env: AZS_SITE=<name> (or --site), AZS_SITE_FLAKE=<hypermodern-nativelink checkout>
#   AZS_FLAKE=<nixos-config checkout> AZS_SSH_PUB=~/.ssh/id_ed25519_b7r6.pub
#   AZS_ADMIN_CIDR=<ip>/32 (default: this box's public IP) AZS_DEPLOY_USER=b7r6
#   AZS_IMAGE=Canonical:ubuntu-24_04-lts:server:latest
set -euo pipefail

log() { printf '// azure-soak // %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
need() { command -v "$1" >/dev/null || die "need $1 on PATH"; }
need az; need jq; need nix; need ssh-keygen; need age

# ── the site, from sites.dhall ────────────────────────────────────────────────
SITE="${AZS_SITE:-}"
if [[ "${1:-}" == "--site" ]]; then SITE="${2:?--site needs a name}"; shift 2; fi
SITE_FLAKE="${AZS_SITE_FLAKE:-$HOME/src/hypermodern/hypermodern-nativelink-0x01}"
FLAKE="${AZS_FLAKE:-$(cd "$(dirname "$0")/.." && pwd)}"
SSH_PUB="${AZS_SSH_PUB:-$HOME/.ssh/id_ed25519_b7r6.pub}"
IMAGE="${AZS_IMAGE:-Canonical:ubuntu-24_04-lts:server:latest}"
ADMIN="${AZS_SSH_USER:-azureuser}"   # the stock Ubuntu image's user, until the kexec installer takes over
DEPLOY_USER="${AZS_DEPLOY_USER:-b7r6}"

usage() { sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }
[[ -n "$SITE" ]] || { log "no site: --site <name> or AZS_SITE"; usage; }

SITE_JSON=$(nix run "$SITE_FLAKE#render-sites" -- "$SITE_FLAKE/examples/sites.dhall" "$SITE" 2>/dev/null) \
  || die "site '$SITE' is not in $SITE_FLAKE/examples/sites.dhall"
s() { jq -r "$1" <<<"$SITE_JSON"; }

RG=$(s .azure.resourceGroup); LOC=$(s .azure.region)
VNET=$(s .azure.vnet); ADDR=$(s .azure.addressSpace); SUBNET=$(s .azure.subnet); SUBNET_PREFIX=$(s .azure.subnetPrefix)
NSG=$(s .azure.nsg); NAT=$(s .azure.natGateway)
STORAGE=$(s .azure.storageAccount); CONTAINER=$(s .azure.container)
TAILNET=$(s .tailnet); TAG_NODES=$(s .tags.nodes); TAG_RIG=$(s .tags.rig)
RIG=$(s .rig.name); BUILDER=$(s .builder.name)
CAS_ENV_SECRET=$(s .casEnvSecret); TS_KEY_SECRET=$(s .tailscaleAuthKeySecret)
mapfile -t NODES < <(s '.nodeNames[]')
ALL=("${NODES[@]}" "$RIG")

vm_size_of() { jq -r --arg h "$1" '(.nodes[] | select(.name==$h) | .size) // (if .rig.name==$h then .rig.size elif .builder.name==$h then .builder.size else empty end)' <<<"$SITE_JSON"; }
vm_disk_of() { jq -r --arg h "$1" '(.nodes[] | select(.name==$h) | .diskGb) // (if .rig.name==$h then .rig.diskGb elif .builder.name==$h then .builder.diskGb else empty end)' <<<"$SITE_JSON"; }
tag_of() { case "$1" in "$RIG") echo "$TAG_RIG" ;; *) echo "$TAG_NODES" ;; esac; }
admin_cidr() { echo "${AZS_ADMIN_CIDR:-$(curl -s -4 https://ifconfig.me)/32}"; }
public_ip_of() { az vm list-ip-addresses -g "$RG" -n "$1" --query '[0].virtualMachine.network.publicIpAddresses[0].ipAddress' -o tsv; }

operator_ids() { # -i … for every operator identity present
  local ids=(); for i in "$HOME/.ssh/id_ed25519_b7r6" "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519_yubikey"; do [[ -r "$i" ]] && ids+=(-i "$i"); done
  printf '%s\n' "${ids[@]}"
}

# ── VMs ────────────────────────────────────────────────────────────────────────
create_vm() { # host [--no-public-ip]
  local h="$1"
  if az vm show -g "$RG" -n "$h" -o none 2>/dev/null; then log "vm $h exists"; return; fi
  log "vm $h: $(vm_size_of "$h"), $(vm_disk_of "$h") GiB Premium OS disk, gen2 Ubuntu, Standard security (no Secure Boot: NixOS kernel/bootloader are unsigned)"
  az vm create -g "$RG" -n "$h" --image "$IMAGE" --size "$(vm_size_of "$h")" \
    --admin-username "$ADMIN" --ssh-key-values "$SSH_PUB" \
    --vnet-name "$VNET" --subnet "$SUBNET" --nsg "" \
    --public-ip-address "${h}-pip" --public-ip-sku Standard \
    --accelerated-networking true \
    --os-disk-name "${h}-os" --os-disk-size-gb "$(vm_disk_of "$h")" --storage-sku Premium_LRS \
    --os-disk-delete-option Delete --nic-delete-option Delete \
    --security-type Standard \
    --no-wait -o none
}

cmd_up() {
  [[ -r "$SSH_PUB" ]] || die "ssh public key $SSH_PUB not readable"
  local cidr; cidr=$(admin_cidr)
  log "site $SITE: resource group $RG in $LOC"
  az group create -n "$RG" -l "$LOC" -o none

  log "nsg $NSG (ssh from $cidr only; Azure default rules keep VNet-internal open, Internet closed)"
  az network nsg create -g "$RG" -n "$NSG" -o none
  az network nsg rule create -g "$RG" --nsg-name "$NSG" -n allow-ssh-admin --priority 100 \
    --direction Inbound --access Allow --protocol Tcp --source-address-prefixes "$cidr" \
    --destination-port-ranges 22 -o none

  log "vnet $VNET $ADDR, subnet $SUBNET $SUBNET_PREFIX"
  az network vnet create -g "$RG" -n "$VNET" --address-prefix "$ADDR" \
    --subnet-name "$SUBNET" --subnet-prefix "$SUBNET_PREFIX" -o none
  az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SUBNET" --network-security-group "$NSG" -o none

  # Egress for nodes WITHOUT a public IP: Azure retired default outbound access
  # for new VNets (2025-09), so a locked-down node would have no route to the
  # Tailscale control plane or to Blob at all. One NAT gateway on the subnet.
  log "nat gateway $NAT (outbound for the subnet; the only egress once nodes lose their public IPs)"
  az network public-ip create -g "$RG" -n "${NAT}-pip" --sku Standard --allocation-method Static -o none
  az network nat gateway create -g "$RG" -n "$NAT" --public-ip-addresses "${NAT}-pip" --idle-timeout 10 -o none
  az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SUBNET" --nat-gateway "$NAT" -o none

  for h in "${ALL[@]}"; do create_vm "$h"; done

  # Host keys while the VMs come up: the secrets a host needs on first boot are
  # encrypted to a key that must exist before the host does.
  cmd_keys "${ALL[@]}"

  log "waiting for the VMs"
  for h in "${ALL[@]}"; do az vm wait -g "$RG" -n "$h" --created; done

  log "storage account $STORAGE + container $CONTAINER (the CAS/AC slow tier)"
  az storage account create -g "$RG" -n "$STORAGE" -l "$LOC" --sku Standard_LRS --kind StorageV2 \
    --min-tls-version TLS1_2 --allow-blob-public-access false -o none
  local key; key=$(az storage account keys list -g "$RG" -n "$STORAGE" --query 'keys[0].value' -o tsv)
  az storage container create --account-name "$STORAGE" --account-key "$key" -n "$CONTAINER" -o none

  cmd_ips
  log "next: azure-soak --site $SITE sas --put ; azure-soak --site $SITE install"
}

cmd_ips() { az vm list-ip-addresses -g "$RG" -o table; }

# ── host keys: generated here, landed in the site flake, listed in both keys.nix ──
keys_listed() { grep -q "^    $1 = \[" "$2/secrets/keys.nix"; }
keys_append() { # host pubkey keys.nix-dir
  local marker='# ── sites (generated: azure-soak.sh --site <s> up appends below this line) ──'
  grep -qF "$marker" "$3/secrets/keys.nix" || die "$3/secrets/keys.nix has no sites marker"
  python3 - "$3/secrets/keys.nix" "$1" "$2" <<'PY'
import sys
p, host, key = sys.argv[1:]
s = open(p).read()
marker = "# ── sites (generated: azure-soak.sh --site <s> up appends below this line) ──"
i = s.index(marker)
j = s.index("\n", i) + 1
# keep the marker's own comment lines together, insert after the comment block
while s[j:].startswith("    #"):
    j = s.index("\n", j) + 1
s = s[:j] + f'    {host} = [ "{key}" ];\n' + s[j:]
open(p, "w").write(s)
PY
}

cmd_keys() {
  local hosts=("$@"); (( ${#hosts[@]} )) || hosts=("${ALL[@]}")
  local work; work=$(mktemp -d); chmod 700 "$work"; trap 'rm -rf "$work"' RETURN
  local changed=0
  for h in "${hosts[@]}"; do
    if [[ -f "$SITE_FLAKE/secrets/agenix/hostkeys/$h.age" ]] && keys_listed "$h" "$SITE_FLAKE" && keys_listed "$h" "$FLAKE"; then
      log "keys $h: present"; continue
    fi
    [[ -f "$SITE_FLAKE/secrets/agenix/hostkeys/$h.age" ]] && die "keys $h: secret exists but $h is not in both keys.nix — reconcile by hand"
    ssh-keygen -q -t ed25519 -N '' -C "root@$h" -f "$work/$h" </dev/null
    local pub; pub=$(cut -d' ' -f1,2 "$work/$h.pub")
    keys_listed "$h" "$SITE_FLAKE" || keys_append "$h" "$pub" "$SITE_FLAKE"
    keys_listed "$h" "$FLAKE" || keys_append "$h" "$pub" "$FLAKE"
    (cd "$SITE_FLAKE" && nix run .#put-secret -- "agenix/hostkeys/$h.age" --from "$work/$h" >&2)
    log "keys $h: generated, landed (operators only), listed in both keys.nix"
    if [[ "$h" == "$RIG" ]]; then
      # the soak driver's root key: on the rig at /var/lib/soak/id_ed25519,
      # authorized for root on the site's nodes (nl-site/common.nix reads the pub)
      ssh-keygen -q -t ed25519 -N '' -C "soak-rig@$h" -f "$work/$h-soak-root" </dev/null
      (cd "$SITE_FLAKE" && nix run .#put-secret -- "agenix/hostkeys/$h-soak-root.age" --from "$work/$h-soak-root" >&2)
      mkdir -p "$SITE_FLAKE/secrets/pub"
      cut -d' ' -f1,2 "$work/$h-soak-root.pub" | sed "s/\$/ soak-rig/" > "$SITE_FLAKE/secrets/pub/$h-soak-root.pub"
      log "keys $h: soak root key landed; public half at secrets/pub/$h-soak-root.pub"
    fi
    changed=1
  done
  if (( changed )); then
    (cd "$SITE_FLAKE" && git add -N secrets/agenix/hostkeys secrets/pub 2>/dev/null || true)
    log "rekeying the site flake's secrets (new hosts in keys.nix)"
    (cd "$SITE_FLAKE" && nix run .#rekey-secrets >&2)
    log "rekeying nixos-config's secrets (new hosts in keys.nix)"
    (cd "$FLAKE" && nix run .#rekey-secrets >&2)
  fi
}

# Decrypt a host's key material into DIR/<host>/… for nixos-anywhere --extra-files.
extra_files_for() { # host dir
  local h="$1" dir="$2/$1"; local ids; mapfile -t ids < <(operator_ids)
  install -d -m 700 "$dir/etc/ssh"
  age -d "${ids[@]}" -o "$dir/etc/ssh/ssh_host_ed25519_key" "$SITE_FLAKE/secrets/agenix/hostkeys/$h.age"
  chmod 600 "$dir/etc/ssh/ssh_host_ed25519_key"
  ssh-keygen -y -f "$dir/etc/ssh/ssh_host_ed25519_key" > "$dir/etc/ssh/ssh_host_ed25519_key.pub"
  if [[ "$h" == "$RIG" ]]; then
    install -d -m 700 "$dir/var/lib/soak"
    age -d "${ids[@]}" -o "$dir/var/lib/soak/id_ed25519" "$SITE_FLAKE/secrets/agenix/hostkeys/$h-soak-root.age"
    chmod 600 "$dir/var/lib/soak/id_ed25519"
    ssh-keygen -y -f "$dir/var/lib/soak/id_ed25519" > "$dir/var/lib/soak/id_ed25519.pub"
  fi
}

cmd_install() {
  local hosts=("$@"); (( ${#hosts[@]} )) || hosts=("${ALL[@]}")
  local work; work=$(mktemp -d); chmod 700 "$work"; trap 'rm -rf "$work"' RETURN
  for h in "${hosts[@]}"; do
    [[ -f "$SITE_FLAKE/secrets/agenix/hostkeys/$h.age" ]] || die "no landed host key for $h (azure-soak --site $SITE keys $h)"
    extra_files_for "$h" "$work"
    local ip; ip=$(public_ip_of "$h"); [[ -n "$ip" ]] || die "no public IP for $h (locked down already?)"
    log "install $h → $ADMIN@$ip (kexec from Ubuntu; disko + the full closure built here)"
    nix run github:nix-community/nixos-anywhere -- \
      --flake "$FLAKE#$h" \
      --extra-files "$work/$h" \
      -i "${SSH_PUB%.pub}" \
      --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null \
      "$ADMIN@$ip"
  done
}

cmd_sas() {
  local key sas expiry
  key=$(az storage account keys list -g "$RG" -n "$STORAGE" --query 'keys[0].value' -o tsv)
  expiry=$(date -u -d '+120 days' +%Y-%m-%dT%H:%MZ)
  sas=$(az storage container generate-sas --account-name "$STORAGE" --account-key "$key" -n "$CONTAINER" \
    --permissions acdlrw --expiry "$expiry" --https-only -o tsv)
  local line="AZURE_CAS_SAS_URL=https://$STORAGE.blob.core.windows.net/$CONTAINER?$sas"
  if [[ "${1:-}" == "--put" ]]; then
    # the value travels by pipe into put-secret (recipients: the site's nodes +
    # operators, from secrets.nix); nothing is printed
    printf '%s\n' "$line" | (cd "$SITE_FLAKE" && nix run .#put-secret -- "agenix/$CAS_ENV_SECRET.age" >&2)
    log "landed agenix/$CAS_ENV_SECRET.age (expires $expiry)"
  else
    echo "$line"
  fi
}

site_auth_key() {
  if [[ -n "${TS_AUTHKEY:-}" ]]; then printf '%s' "$TS_AUTHKEY"; return; fi
  local age_file="$SITE_FLAKE/secrets/agenix/$TS_KEY_SECRET.age"
  [[ -f "$age_file" ]] || die "no TS_AUTHKEY and no $age_file"
  local ids; mapfile -t ids < <(operator_ids)
  local key; key=$(age -d "${ids[@]}" "$age_file" | tr -d '\n')
  # An auth key is `tskey-auth-…`; refuse anything else (a pasted command line,
  # an API token, an OAuth client secret) before it reaches `tailscale up`.
  [[ "$key" == tskey-auth-* ]] || die "the decrypted secret is not a Tailscale AUTH key (expected tskey-auth-…, got '${key:0:11}…')"
  printf '%s' "$key"
}

# ssh target + options for a host: the rig directly, a node via the rig.
ssh_opts_for() { # host -> prints "-o ... [-J user@rig-ip]"
  local base="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_PUB%.pub}"
  case "$1" in
    "$RIG"|"$BUILDER") printf '%s' "$base" ;;
    *) printf '%s -o ProxyJump=%s@%s' "$base" "$DEPLOY_USER" "$(public_ip_of "$RIG")" ;;
  esac
}
ssh_dest_for() { # host -> user@addr (tailnet name for a node, public IP for the rig / builder)
  case "$1" in
    "$RIG"|"$BUILDER") printf '%s@%s' "$DEPLOY_USER" "$(public_ip_of "$1")" ;;
    *) printf '%s@%s.%s' "$DEPLOY_USER" "$1" "$TAILNET" ;;
  esac
}

# Enroll hosts that are still in NeedsLogin (the declarative autoconnect only
# fires with a valid key at boot). Runs `tailscale up` with the SAME flags the
# NixOS module uses, plus the key; state persists in /var/lib/tailscale.
cmd_enroll() {
  local hosts=("$@"); (( ${#hosts[@]} )) || hosts=("${ALL[@]}")
  local key; key=$(site_auth_key)
  for h in "${hosts[@]}"; do
    local tag; tag=$(tag_of "$h")
    local opts dest; opts=$(ssh_opts_for "$h"); dest=$(ssh_dest_for "$h")
    log "enroll $h -> $dest ($tag)"
    # the key travels on stdin, never in argv/logs; same up-flags as the NixOS module
    # shellcheck disable=SC2086
    printf '%s' "$key" | ssh $opts "$dest" \
      "k=\$(cat); sudo tailscale up --reset --accept-dns --ssh=false --accept-routes --advertise-tags=$tag --auth-key=\"\$k\" >/dev/null 2>&1; sudo tailscale status --json | python3 -c \"import json,sys; d=json.load(sys.stdin); print(d['BackendState'], d['Self']['DNSName'], ' '.join(d['Self'].get('TailscaleIPs',[])), 'tags=' + ','.join(d['Self'].get('Tags') or []))\""
  done
}

# Advertise the site tags on ALREADY-enrolled hosts. A plain `tailscale up
# --advertise-tags` applies (the enrolling user is a tag owner); the auth-key
# path does not take tags, so enroll + tag are two steps. Before the operator
# has pasted the generated policy, a tag unknown to the tailnet is refused and
# the host stays enrolled untagged (allowed), so this is safe to rerun.
cmd_tag() {
  local hosts=("$@"); (( ${#hosts[@]} )) || hosts=("${ALL[@]}")
  for h in "${hosts[@]}"; do
    local tag; tag=$(tag_of "$h")
    local opts dest; opts=$(ssh_opts_for "$h"); dest=$(ssh_dest_for "$h")
    # shellcheck disable=SC2086
    ssh $opts "$dest" "sudo timeout 30 tailscale up --accept-dns --ssh=false --accept-routes --advertise-tags=$tag >/dev/null 2>&1; sudo tailscale status --json | python3 -c \"import json,sys; d=json.load(sys.stdin); print('$h', d['BackendState'], 'tags=' + ','.join(d['Self'].get('Tags') or []))\""
  done
}

# Lock down: the fleet nodes lose their public IPs entirely; the rig keeps its
# public IP + the admin-only ssh NSG rule and becomes the bastion (the
# operator's box is NOT on the site's tailnet — it reaches the nodes with
# ProxyJump through the rig, which is). `deploy` uses exactly that.
cmd_lockdown() {
  az network nat gateway show -g "$RG" -n "$NAT" -o none 2>/dev/null \
    || die "no NAT gateway on the subnet — removing public IPs would cut the nodes' egress entirely (run: azure-soak --site $SITE up)"
  for h in "${NODES[@]}"; do
    log "$h: detaching + deleting public IP"
    az network nic ip-config update -g "$RG" --nic-name "${h}VMNic" -n "ipconfig${h}" --remove publicIpAddress -o none || true
    az network public-ip delete -g "$RG" -n "${h}-pip" || true
  done
  log "the rig keeps ${RIG}-pip and the allow-ssh-admin rule (bastion)"
}

# Build here, copy (public paths substituted on the destination), register the
# system profile, switch. AZS_BUILDERS='ssh://…' (what `builder line` prints)
# makes the build itself happen on the site's builder; the copy still leaves
# from here.
cmd_deploy() {
  local hosts=("$@"); (( ${#hosts[@]} )) || hosts=("${ALL[@]}")
  for h in "${hosts[@]}"; do
    local out; out=$(nix build --no-link --print-out-paths ${AZS_BUILDERS:+--builders "$AZS_BUILDERS"} \
      "$FLAKE#nixosConfigurations.$h.config.system.build.toplevel" 2>&1 | grep '^/nix/store' | tail -1)
    [[ -n "$out" ]] || die "build failed for $h"
    local opts dest; opts=$(ssh_opts_for "$h"); dest=$(ssh_dest_for "$h")
    log "deploy $h: $out -> $dest"
    # shellcheck disable=SC2086
    NIX_SSHOPTS="$opts" nix copy --substitute-on-destination --to "ssh://$dest" "$out"
    # shellcheck disable=SC2086,SC2029
    ssh $opts "$dest" "sudo nix-env -p /nix/var/nix/profiles/system --set $out && sudo $out/bin/switch-to-configuration switch"
  done
}

cmd_status() {
  az resource list -g "$RG" -o table 2>/dev/null || { echo "no resource group $RG"; return; }
  az vm list -g "$RG" -d -o table
}

cmd_down() {
  log "deleting resource group $RG (all VMs, disks, the storage account and its CAS)"
  az group delete -n "$RG" --yes --no-wait
}

# ── the builder ────────────────────────────────────────────────────────────────
# A D16s_v5 in the site's VNet with its own public IP (the same admin-only ssh
# rule as the rig): a Nix remote builder for the laptop, and a box to deploy
# from. Installed like any site host (role `builder` in nl-site), so its host
# key is pre-generated and pinned in the `--builders` line. Deallocated when
# idle: a stopped VM bills only its disk.
cmd_builder() {
  case "${1:-}" in
    up)
      az group show -n "$RG" -o none 2>/dev/null || die "no resource group $RG (azure-soak --site $SITE up first)"
      create_vm "$BUILDER"
      cmd_keys "$BUILDER"
      az vm wait -g "$RG" -n "$BUILDER" --created
      if az vm get-instance-view -g "$RG" -n "$BUILDER" --query 'instanceView.statuses[?starts_with(code, `PowerState`)].code' -o tsv | grep -q deallocated; then
        az vm start -g "$RG" -n "$BUILDER" -o none
      fi
      cmd_install "$BUILDER"
      cmd_builder line
      ;;
    down) log "deallocating $BUILDER (disk kept)"; az vm deallocate -g "$RG" -n "$BUILDER" -o none ;;
    start) az vm start -g "$RG" -n "$BUILDER" -o none; cmd_builder line ;;
    rm) log "deleting $BUILDER"; az vm delete -g "$RG" -n "$BUILDER" --yes -o none; az network public-ip delete -g "$RG" -n "${BUILDER}-pip" -o none || true ;;
    status) az vm get-instance-view -g "$RG" -n "$BUILDER" --query '{name:name,power:instanceView.statuses[1].displayStatus,size:hardwareProfile.vmSize}' -o table ;;
    line)
      local ip pub; ip=$(public_ip_of "$BUILDER"); [[ -n "$ip" ]] || die "$BUILDER has no public IP (is it up?)"
      pub=$(grep "^    $BUILDER = \[" "$SITE_FLAKE/secrets/keys.nix" | sed 's/.*"\(ssh-ed25519 [^"]*\)".*/\1/' | base64 -w0)
      echo "ssh://$DEPLOY_USER@$ip x86_64-linux ${SSH_PUB%.pub} 16 1 big-parallel,kvm,nixos-test - $pub"
      log "use: AZS_BUILDERS='<that line>' azure-soak --site $SITE deploy …  or  nix build --builders '<that line>' …"
      ;;
    *) usage ;;
  esac
}

case "${1:-}" in
  up) cmd_up ;;
  keys) shift; cmd_keys "$@" ;;
  ips) cmd_ips ;;
  install) shift; cmd_install "$@" ;;
  sas) shift; cmd_sas "$@" ;;
  enroll) shift; cmd_enroll "$@" ;;
  tag) shift; cmd_tag "$@" ;;
  lockdown) cmd_lockdown ;;
  deploy) shift; cmd_deploy "$@" ;;
  status) cmd_status ;;
  down) cmd_down ;;
  builder) shift; cmd_builder "$@" ;;
  *) usage ;;
esac
