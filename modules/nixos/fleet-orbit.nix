# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                          // hyper-modern-nixos // fleet-orbit
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Secureframe's device agent, OFF BY DEFAULT. Secureframe IS Fleet: the agent is
# fleetd's `orbit` launcher (→ packages/fleet-orbit, the pinned `orbit` binary),
# and orbit self-updates osqueryd + fleet-desktop into its --root-dir and execs
# those DYNAMICALLY-linked binaries, so programs.nix-ld must be on (fleet-wide
# default).
#
# Secureframe does NOT expose a copyable enroll token. Instead "Device
# Management → Download Agent" builds a PERSONALIZED .deb/.rpm whose
# /etc/default/orbit holds the ORBIT_* env (fleet URL + enroll secret + update
# channels) and whose systemd unit passes an osquery --specified_identifier
# (a user:device:host UUID triple) that links the box to its Secureframe device
# record. We reproduce that unit declaratively:
#   - environmentFile : the agenix-decrypted copy of that /etc/default/orbit
#                       (ORBIT_ENROLL_SECRET lives here → agenix, never the store)
#   - hostIdentifier  : the --specified_identifier triple from the .deb's unit
#
# To (re)provision: download a fresh agent .deb from Secureframe, extract
# /etc/default/orbit → agenix secret, and copy the --specified_identifier out of
# its usr/lib/systemd/system/orbit.service into hostIdentifier.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.fleet-orbit;
in
{
  options.hyper-modern-nixos.fleet-orbit = {
    enable = lib.mkEnableOption "Secureframe fleet-orbit device agent (osquery enrollment)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.fleet-orbit;
      defaultText = lib.literalExpression "pkgs.fleet-orbit";
      description = "The fleet-orbit package providing the `orbit` launcher.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.str;
      example = "/run/agenix/fleet-orbit-env";
      description = ''
        Path to the agenix-decrypted ORBIT_* environment file (the Secureframe
        .deb's /etc/default/orbit: ORBIT_FLEET_URL, ORBIT_ENROLL_SECRET,
        ORBIT_UPDATE_URL, channels, ORBIT_FLEET_DESKTOP). Holds the enroll
        secret, so it MUST be an agenix path, never the nix store.
      '';
    };

    hostIdentifier = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "edaca163-…:aec2d51b-…:17a29c92-…";
      description = ''
        Secureframe's osquery --specified_identifier (the user:device:host UUID
        triple from the personalized .deb's orbit.service). Links this host to
        its Secureframe device record so it reports as the intended device
        instead of enrolling as a new one. Not a credential, but installer-
        specific; refresh it if you re-download the agent.
      '';
    };

    rootDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/orbit";
      description = "orbit working dir (self-updated binaries + node key). StateDirectory-persisted.";
    };

    cpuQuota = lib.mkOption {
      type = lib.types.str;
      default = "20%";
      description = "CPU cap, matching Secureframe's shipped unit (CPUQuota=20%).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "hyper-modern-nixos.fleet-orbit.package is null — set it to pkgs.fleet-orbit.";
      }
    ];

    # orbit's self-updated osqueryd/fleet-desktop are dynamically linked.
    hyper-modern-nixos.nix-ld.enable = lib.mkDefault true;

    systemd.services.orbit = {
      description = "Orbit osquery (Secureframe Fleet device agent)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        EnvironmentFile = cfg.environmentFile;
        # Mirror the Secureframe unit: orbit flags, then `--`, then osquery flags.
        ExecStart = lib.concatStringsSep " " (
          [
            "${cfg.package}/bin/orbit"
            "--root-dir ${cfg.rootDir}"
          ]
          ++ lib.optionals (cfg.hostIdentifier != null) [
            "--"
            "--host_identifier specified"
            "--specified_identifier ${cfg.hostIdentifier}"
          ]
        );
        Restart = "always";
        RestartSec = 1;
        StateDirectory = "orbit";
        StateDirectoryMode = "0700";
        KillMode = "control-group";
        KillSignal = "SIGTERM";
        CPUQuota = cfg.cpuQuota;
      };
    };
  };
}
