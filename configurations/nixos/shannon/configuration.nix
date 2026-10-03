{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./hardware-configuration.nix
    inputs.agenix.nixosModules.default
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "shannon";
  networking.networkmanager.enable = true;

  # ── attic api-server replica (module self-wires its secrets) ────────────────

  hyper-modern-nixos.attic-node = {
    enable = true;
    profile = "replica";
  };

  # ── OTel agent (host metrics + journald → watchtower gateway) ──────────────

  hyper-modern-nixos.observability.otel.agent.enable = true;

  # ── CoreDNS as this node's own resolver ─────────────────────────────────────
  # Resolves *.sju1.s4.gl — git.s4.gl among them, where the continuity and
  # straylight-nvidia-sdk flake inputs live — which MagicDNS can't. Same
  # bootstrap order as gossamer: coredns has to come up before those inputs
  # will fetch on this box.
  hyper-modern-nixos.coredns.enable = true;

  # ── Tailscale safety net ────────────────────────────────────────────────────

  age.secrets.tailscale-auth-key.file = ../../../secrets/agenix/machines/tailscale-auth-key.age;
  hyper-modern-nixos.network.tailscale.authKeyFile = "/run/agenix/tailscale-auth-key";
  hyper-modern-nixos.network.tailscale.exitNodeRotation.enable = true;

  # ── restic → Cloudflare R2 backups ─────────────────────────────────────────

  # Per-host repo (backups-restic/shannon). FIRST init:  nix run .#restic-init -- shannon
  hyper-modern-nixos.backup = {
    enable = true;
    passwordSecret = "restic-password";
    environmentSecret = "restic-r2-env.shannon";
    paths = [ "/home" ];
  };

  # ── NVIDIA dGPU (RTX 4050) — the HDMI port is hardwired to it ───────────────
  # Without the driver the connector never enumerates in DRM, so external
  # HDMI displays are dead. amdgpu (Radeon 890M) stays primary; the dGPU
  # runs in offload mode and wakes when an output or app needs it.
  hyper-modern-nixos.nvidia.enable = true;

  hardware.nvidia.prime = {
    amdgpuBusId = "PCI:197:0:0"; # c5:00.0 Radeon 880M/890M
    nvidiaBusId = "PCI:196:0:0"; # c4:00.0 RTX 4050 Max-Q
    offload = {
      enable = true;
      enableOffloadCmd = true;
    };
  };

  environment.variables = {
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
  };

  # ── INTERIM: trust the s4.gl stopgap CA (expires 2026-10-27) ───────────────
  # Njalla's API is down, so the *.sju1.s4.gl wildcard couldn't renew; a
  # 30-day CA on watchtower signs the interim cert. HSTS on auth.s4.gl means
  # click-through is impossible — trust must be real. DELETE this (and the
  # .pem) once Let's Encrypt renewal lands.
  security.pki.certificateFiles = [ ./interim-s4gl-ca.pem ];

  programs.firefox.enable = true;
  # Firefox reads the system store only with enterprise roots on. Harmless
  # to keep after the interim CA is gone.
  programs.firefox.policies.Certificates.ImportEnterpriseRoots = true;

  security.sudo.wheelNeedsPassword = false;

  time.timeZone = "America/New_York";
  services.printing.enable = true;
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # ── Internal mic gain fix (ALC294, card "Generic_1" @ c5:00.6) ─────────────
  # The HDA driver comes up with Capture +30dB AND Internal Mic Boost +30dB;
  # +60dB total rails the DMIC into full-scale static. Boost 0 / Capture 70%
  # gives clean speech-level capture. (The ACP70 coprocessor has no machine
  # driver on this kernel — "No matching ASoC machine driver found" — so the
  # HDA path IS the internal mic.)
  systemd.services.fix-mic-gain = {
    wantedBy = [ "multi-user.target" ];
    after = [ "sound.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      for c in /proc/asound/card*; do
        if [ "$(cat $c/id)" = "Generic_1" ]; then
          n=''${c#/proc/asound/card}
          ${pkgs.alsa-utils}/bin/amixer -c "$n" sset 'Internal Mic Boost' 0
          ${pkgs.alsa-utils}/bin/amixer -c "$n" sset Capture 70%
        fi
      done
    '';
  };

  # ── Per-host monitor & display config ──────────────────────────────────────
  home-manager.users.b7r6 = {
    hyper-modern-nixos = {
      hyprland.monitors = (import ../../../lib/monitors.nix).shannon;

      themes.display = {
        profile = "oled";
        highDPI = true;
        width = 2880;
        height = 1800;
      };

      # ── The rice ─────────────────────────────────────────────────────────
      # Same shell as the Sparks: new-suzuki + wintermute, exclusive. No
      # cudaField — the field kernel is Spark-only (sm_121, aarch64 check
      # gate); the QML AnimatedWallpaper renders the field here.
      new-suzuki = {
        enable = true;
        exclusive = true;
      };
    };
  };

  system.stateVersion = "25.05"; # Did you read the comment?
}
