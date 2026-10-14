#!/usr/bin/env bash
# azure-soak — infra for the Azure NativeLink soak fleet (docs/azure-soak-fleet.md).
#
# Plain `az` CLI, one resource group, four regional (non-zonal) VMs, one
# storage account. Run from the builder (shannon) with `az login` done.
#
#   azure-soak up                    RG, VNet/NSG, 4 VMs, storage + container
#   azure-soak ips                   public/private IPs of the VMs
#   azure-soak install [host...]     nixos-anywhere each VM (default: all)
#   azure-soak sas                   print AZURE_CAS_SAS_URL=… (for the agenix env)
#   azure-soak enroll [host...]      tailscale up on hosts stuck in NeedsLogin, with the
#                                    site's auth key (env TS_AUTHKEY, or decrypted from the
#                                    hypermodern-nativelink agenix tree with the operator key)
#   azure-soak tag [host...]         advertise tag:nl-soak / tag:nl-rig on enrolled hosts
#   azure-soak lockdown              nodes lose their public IPs; the rig stays the ssh bastion
#   azure-soak deploy [host...]      build here, copy + switch (nodes via ProxyJump through the rig)
#   azure-soak status                what exists
#   azure-soak down                  delete the resource group (everything)
#
# Env (defaults): AZS_RG=nl-soak-wus2 AZS_LOCATION=westus2 AZS_NODE_SIZE=Standard_D8s_v5
#   AZS_RIG_SIZE=Standard_D4s_v5 AZS_NODE_DISK_GB=256 AZS_RIG_DISK_GB=128
#   AZS_STORAGE=<globally-unique, 3-24 lowercase alnum> AZS_SSH_PUB=~/.ssh/id_ed25519_b7r6.pub
#   AZS_KEYS_DIR=<dir with <host>/etc/ssh/ssh_host_ed25519_key…> (install)
#   AZS_FLAKE=<flake dir> (install)  AZS_ADMIN_CIDR=<ip>/32 (default: this box's public IP)
set -euo pipefail

RG="${AZS_RG:-nl-soak-wus2}"
LOC="${AZS_LOCATION:-westus2}"
VNET="${AZS_VNET:-nl-soak-vnet}"
SUBNET="nodes"
NSG="${AZS_NSG:-nl-soak-nsg}"
NODE_SIZE="${AZS_NODE_SIZE:-Standard_D8s_v5}"
RIG_SIZE="${AZS_RIG_SIZE:-Standard_D4s_v5}"
NODE_DISK="${AZS_NODE_DISK_GB:-256}"
RIG_DISK="${AZS_RIG_DISK_GB:-128}"
IMAGE="${AZS_IMAGE:-Canonical:ubuntu-24_04-lts:server:latest}"
ADMIN="${AZS_SSH_USER:-azureuser}"   # root once a target is already in the kexec installer
SSH_PUB="${AZS_SSH_PUB:-$HOME/.ssh/id_ed25519_b7r6.pub}"
STORAGE="${AZS_STORAGE:-nlsoakcas$(id -u)}"
CONTAINER="${AZS_CONTAINER:-nativelink-cas}"
NODES=(nl-az-a nl-az-b nl-az-c)
RIG=nl-az-rig
ALL=("${NODES[@]}" "$RIG")

log() { printf '// azure-soak // %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

need() { command -v "$1" >/dev/null || die "need $1 on PATH"; }
need az; need jq

admin_cidr() { echo "${AZS_ADMIN_CIDR:-$(curl -s -4 https://ifconfig.me)/32}"; }

vm_size_of() { case "$1" in "$RIG") echo "$RIG_SIZE" ;; *) echo "$NODE_SIZE" ;; esac; }
vm_disk_of() { case "$1" in "$RIG") echo "$RIG_DISK" ;; *) echo "$NODE_DISK" ;; esac; }

cmd_up() {
  [[ -r "$SSH_PUB" ]] || die "ssh public key $SSH_PUB not readable"
  local cidr; cidr=$(admin_cidr)
  log "resource group $RG in $LOC"
  az group create -n "$RG" -l "$LOC" -o none

  log "nsg $NSG (ssh from $cidr only; Azure default rules keep VNet-internal open, Internet closed)"
  az network nsg create -g "$RG" -n "$NSG" -o none
  az network nsg rule create -g "$RG" --nsg-name "$NSG" -n allow-ssh-admin --priority 100 \
    --direction Inbound --access Allow --protocol Tcp --source-address-prefixes "$cidr" \
    --destination-port-ranges 22 -o none

  log "vnet $VNET 10.42.0.0/16, subnet $SUBNET 10.42.0.0/24 (10.42.16.0/20 reserved for a later AKS leg)"
  az network vnet create -g "$RG" -n "$VNET" --address-prefix 10.42.0.0/16 \
    --subnet-name "$SUBNET" --subnet-prefix 10.42.0.0/24 -o none
  az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SUBNET" --network-security-group "$NSG" -o none

  # Egress for nodes WITHOUT a public IP: Azure retired default outbound access
  # for new VNets (2025-09), so a locked-down node would have no route to the
  # Tailscale control plane or to Blob at all. One NAT gateway on the subnet.
  log "nat gateway $NSG-nat (outbound for the subnet; the only egress once nodes lose their public IPs)"
  az network public-ip create -g "$RG" -n nl-soak-nat-pip --sku Standard --allocation-method Static -o none
  az network nat gateway create -g "$RG" -n nl-soak-nat --public-ip-addresses nl-soak-nat-pip --idle-timeout 10 -o none
  az network vnet subnet update -g "$RG" --vnet-name "$VNET" -n "$SUBNET" --nat-gateway nl-soak-nat -o none

  for h in "${ALL[@]}"; do
    if az vm show -g "$RG" -n "$h" -o none 2>/dev/null; then log "vm $h exists"; continue; fi
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
  done
  log "waiting for the VMs"
  for h in "${ALL[@]}"; do az vm wait -g "$RG" -n "$h" --created; done

  log "storage account $STORAGE + container $CONTAINER (the CAS/AC slow tier)"
  az storage account create -g "$RG" -n "$STORAGE" -l "$LOC" --sku Standard_LRS --kind StorageV2 \
    --min-tls-version TLS1_2 --allow-blob-public-access false -o none
  local key; key=$(az storage account keys list -g "$RG" -n "$STORAGE" --query 'keys[0].value' -o tsv)
  az storage container create --account-name "$STORAGE" --account-key "$key" -n "$CONTAINER" -o none

  cmd_ips
  log "next: azure-soak sas  →  edit-secret agenix/machines/nativelink-azure-env.age ; azure-soak install"
}

cmd_ips() {
  az vm list-ip-addresses -g "$RG" -o table
}

public_ip_of() {
  az vm list-ip-addresses -g "$RG" -n "$1" --query '[0].virtualMachine.network.publicIpAddresses[0].ipAddress' -o tsv
}

cmd_install() {
  local flake="${AZS_FLAKE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  local keys="${AZS_KEYS_DIR:?set AZS_KEYS_DIR to the pre-generated host-key tree (<host>/etc/ssh/...)}"
  local hosts=("$@"); (( ${#hosts[@]} )) || hosts=("${ALL[@]}")
  for h in "${hosts[@]}"; do
    [[ -f "$keys/$h/etc/ssh/ssh_host_ed25519_key" ]] || die "no host key for $h under $keys"
    local ip; ip=$(public_ip_of "$h"); [[ -n "$ip" ]] || die "no public IP for $h (locked down already?)"
    log "install $h → $ADMIN@$ip (kexec from Ubuntu; disko + the full closure built here)"
    nix run github:nix-community/nixos-anywhere -- \
      --flake "$flake#$h" \
      --extra-files "$keys/$h" \
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
  echo "AZURE_CAS_SAS_URL=https://$STORAGE.blob.core.windows.net/$CONTAINER?$sas"
}

site_auth_key() {
  if [[ -n "${TS_AUTHKEY:-}" ]]; then printf '%s' "$TS_AUTHKEY"; return; fi
  local age_file="${AZS_SITE_FLAKE:-$HOME/src/hypermodern/hypermodern-nativelink-0x01}/secrets/agenix/tailscale-auth-key.age"
  [[ -f "$age_file" ]] || die "no TS_AUTHKEY and no $age_file"
  local ids=()
  for i in "$HOME/.ssh/id_ed25519_b7r6" "$HOME/.ssh/id_ed25519"; do [[ -r "$i" ]] && ids+=(-i "$i"); done
  local key; key=$(nix shell nixpkgs#age -c age -d "${ids[@]}" "$age_file" | tr -d '\n')
  # An auth key is `tskey-auth-…`; refuse anything else (a pasted command line,
  # an API token, an OAuth client secret) before it reaches `tailscale up`.
  [[ "$key" == tskey-auth-* ]] || die "the decrypted secret is not a Tailscale AUTH key (expected tskey-auth-…, got '${key:0:11}…')"
  printf '%s' "$key"
}

# Enroll hosts that are still in NeedsLogin (the declarative autoconnect only
# fires with a valid key at boot). Runs `tailscale up` with the SAME flags the
# NixOS module uses, plus the key; state persists in /var/lib/tailscale.
cmd_enroll() {
  local hosts=("$@"); (( ${#hosts[@]} )) || hosts=("${ALL[@]}")
  local key; key=$(site_auth_key)
  for h in "${hosts[@]}"; do
    local tag; case "$h" in "$RIG") tag="tag:nl-rig" ;; *) tag="tag:nl-soak" ;; esac
    local opts dest; opts=$(ssh_opts_for "$h"); dest=$(ssh_dest_for "$h")
    log "enroll $h -> $dest ($tag)"
    # the key travels on stdin, never in argv/logs; same up-flags as the NixOS module
    # shellcheck disable=SC2086
    printf '%s' "$key" | ssh $opts "$dest" \
      "k=\$(cat); sudo tailscale up --reset --accept-dns --ssh=false --accept-routes --advertise-tags=$tag --auth-key=\"\$k\" >/dev/null 2>&1; sudo tailscale status --json | python3 -c \"import json,sys; d=json.load(sys.stdin); print(d['BackendState'], d['Self']['DNSName'], ' '.join(d['Self'].get('TailscaleIPs',[])), 'tags=' + ','.join(d['Self'].get('Tags') or []))\""
  done
}

# Lock down: the three fleet nodes lose their public IPs entirely; the rig
# keeps its public IP + the admin-only ssh NSG rule and becomes the bastion
# (the builder is NOT on the site's tailnet — it reaches the nodes with
# ProxyJump through the rig, which is). `deploy` below uses exactly that.
# Advertise the site tags on ALREADY-enrolled hosts. A plain `tailscale up
# --advertise-tags` applies (the enrolling user is a tag owner); the auth-key
# path does not take tags, so enroll + tag are two steps.
cmd_tag() {
  local hosts=("$@"); (( ${#hosts[@]} )) || hosts=("${ALL[@]}")
  for h in "${hosts[@]}"; do
    local tag; case "$h" in "$RIG") tag="tag:nl-rig" ;; *) tag="tag:nl-soak" ;; esac
    local opts dest; opts=$(ssh_opts_for "$h"); dest=$(ssh_dest_for "$h")
    # shellcheck disable=SC2086
    ssh $opts "$dest" "sudo timeout 30 tailscale up --accept-dns --ssh=false --accept-routes --advertise-tags=$tag >/dev/null 2>&1; sudo tailscale status --json | python3 -c \"import json,sys; d=json.load(sys.stdin); print('$h', d['BackendState'], 'tags=' + ','.join(d['Self'].get('Tags') or []))\""
  done
}

cmd_lockdown() {
  az network nat gateway show -g "$RG" -n nl-soak-nat -o none 2>/dev/null \
    || die "no NAT gateway on the subnet — removing public IPs would cut the nodes' egress entirely (run: azure-soak up)"
  for h in "${NODES[@]}"; do
    log "$h: detaching + deleting public IP"
    az network nic ip-config update -g "$RG" --nic-name "${h}VMNic" -n "ipconfig${h}" --remove publicIpAddress -o none || true
    az network public-ip delete -g "$RG" -n "${h}-pip" || true
  done
  log "the rig keeps ${RIG}-pip and the allow-ssh-admin rule (bastion)"
}

# ssh target + options for a host: the rig directly, a node via the rig.
ssh_opts_for() { # host -> prints "-o ... [-J user@rig-ip]"
  local base="-o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${SSH_PUB%.pub}"
  if [[ "$1" == "$RIG" ]]; then printf '%s' "$base"; else printf '%s -o ProxyJump=%s@%s' "$base" "${AZS_DEPLOY_USER:-b7r6}" "$(public_ip_of "$RIG")"; fi
}
ssh_dest_for() { # host -> user@addr (tailnet name for a node, public IP for the rig)
  if [[ "$1" == "$RIG" ]]; then printf '%s@%s' "${AZS_DEPLOY_USER:-b7r6}" "$(public_ip_of "$RIG")"; else printf '%s@%s.%s' "${AZS_DEPLOY_USER:-b7r6}" "$1" "${AZS_TAILNET:-tail8ec1af.ts.net}"; fi
}

# Build here, copy (public paths substituted on the destination), register the
# system profile, switch. The same-arch path deploy-fleet takes, minus the
# tailnet assumption: the builder is off-site, so nodes are reached via the rig.
cmd_deploy() {
  local flake="${AZS_FLAKE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  local hosts=("$@"); (( ${#hosts[@]} )) || hosts=("${ALL[@]}")
  for h in "${hosts[@]}"; do
    local out; out=$(nix build --no-link --print-out-paths "$flake#nixosConfigurations.$h.config.system.build.toplevel" 2>&1 | grep '^/nix/store' | tail -1)
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

case "${1:-}" in
  up) cmd_up ;;
  ips) cmd_ips ;;
  install) shift; cmd_install "$@" ;;
  sas) cmd_sas ;;
  enroll) shift; cmd_enroll "$@" ;;
  tag) shift; cmd_tag "$@" ;;
  lockdown) cmd_lockdown ;;
  deploy) shift; cmd_deploy "$@" ;;
  status) cmd_status ;;
  down) cmd_down ;;
  *) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
