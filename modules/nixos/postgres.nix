# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                           // hyper-modern-nixos // databases
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# PostgreSQL + Redis, OFF BY DEFAULT.
#
# Previously this module unconditionally enabled postgres on EVERY host. It is
# now opt-in via `hyper-modern-nixos.databases.postgres.enable`, because the
# fleet runs exactly one shared postgres (on watchtower) that backs the central
# atticd cache's metadata. Other hosts don't need a local postgres.
#
# ── Tailnet exposure (best-practice, defense in depth) ──────────────────────
# When `tailnet.enable` is set, exposure is gated at TWO layers:
#   1. firewall: port 5432 is opened ONLY on `tailnet.interface` (tailscale0),
#      via networking.firewall.interfaces. The firewall is ON fleet-wide (see
#      network.nix), so this interface-scoped rule actually bites everywhere —
#      5432 is reachable on the tailnet but never on a public interface.
#   2. pg_hba: md5 auth permitted only from loopback + the tailnet CIDRs.
# atticd instances on other hosts connect over MagicDNS.
{
  config,
  lib,
  pkgs,
  # `flake` (specialArg) locates the in-repo agenix secrets for self-wiring the
  # pgBackRest R2 env. Defaulted null so contexts importing this module without
  # it (e.g. the attic-cache nixosTest, which doesn't use PITR) still evaluate.
  flake ? null,
  ...
}:
let
  cfg = config.hyper-modern-nixos.databases;
  machineSecrets = flake.self + "/secrets/agenix/machines";
in
{
  options.hyper-modern-nixos.databases = {
    postgres = {
      enable = lib.mkEnableOption "PostgreSQL server (off by default)";

      package = lib.mkPackageOption pkgs "postgresql_16" { };

      tailnet = {
        enable = lib.mkEnableOption ''
          listen on the tailscale0 address and allow md5-authenticated
          connections from the tailnet CGNAT range (100.64.0.0/10)
        '';

        interface = lib.mkOption {
          type = lib.types.str;
          default = "tailscale0";
          description = "Interface whose address postgres additionally binds.";
        };

        cidrs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "100.64.0.0/10" # tailscale CGNAT range (IPv4)
            "fd7a:115c:a1e0::/48" # tailscale ULA range (IPv6)
          ];
          description = "Source CIDRs permitted (md5) in pg_hba for tailnet access.";
        };
      };

      ensureDatabases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "atticd" ];
        description = "Databases to create declaratively (services.postgresql.ensureDatabases).";
      };

      ensureUsers = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [ ];
        description = ''
          Roles to create declaratively (services.postgresql.ensureUsers).
          Peer-auth only by default; for password auth set a password out of
          band (ALTER ROLE … PASSWORD) or via an agenix-fed init — NixOS won't
          put a password in the store.
        '';
      };

      settings = lib.mkOption {
        type = lib.types.attrs;
        default = { };
        description = "Extra settings merged into services.postgresql.settings.";
      };

      # ── Declarative role passwords ──────────────────────────────────────────
      # ensureUsers cannot set a password. This wires a post-start oneshot that
      # runs `ALTER ROLE <name> PASSWORD …` for each entry, sourcing the password
      # from an AGENIX SECRET (by name) and taking the named env var. Idempotent
      # on every boot/rebuild; the password is read at runtime and NEVER enters
      # the store. Single source of truth: the SAME secret the client (e.g.
      # atticd) reads PGPASSWORD from, so they can't drift.
      #
      # Purely declarative + host-agnostic: this module GRANTS the postgres user
      # read access to the named secret (age.secrets.<name>.group = "postgres",
      # mode 0440), so the postgres-run oneshot can read it without any manual
      # chown. The secret stays root-owned; atticd reads it via systemd
      # EnvironmentFile (as root, pre-DynamicUser) so group-read doesn't affect it.
      rolePasswords = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              secret = lib.mkOption {
                type = lib.types.str;
                description = "agenix secret NAME (decrypts to /run/agenix/<name>) to source the password from.";
              };
              var = lib.mkOption {
                type = lib.types.str;
                default = "PGPASSWORD";
                description = "Env var name within the secret holding the role password.";
              };
            };
          }
        );
        default = { };
        example = {
          atticd.secret = "atticd-rs256";
        };
        description = "role name -> { secret; var; } to set that role's password declaratively.";
      };

      # ── Backup ──────────────────────────────────────────────────────────────
      # Logical dumps now; a PITR/WAL-archiving seam for later (see
      # docs/architecture/state-and-backup.md). We back up DUMPS, never the live
      # cluster dir — backing up running data files is corruption-prone and
      # version-locked; logical dumps also restore across PG majors.
      backup = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = cfg.postgres.enable;
          defaultText = "config.hyper-modern-nixos.databases.postgres.enable";
          description = ''
            Run scheduled logical dumps (pg_dumpall → zstd) into `dumpDir`, and
            classify that dir as `authoritative` state so restic backs it up.
            Defaults on whenever postgres is enabled.
          '';
        };

        dumpDir = lib.mkOption {
          type = lib.types.str;
          default = "/var/backup/postgres";
          description = ''
            Directory the logical dumps are written to. Declared as
            `authoritative` state (persisted across an impermanence reboot AND
            backed up to R2). Keep it OFF the postgres cluster dir.
          '';
        };

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = "systemd OnCalendar for the dump timer.";
        };

        keep = lib.mkOption {
          type = lib.types.int;
          default = 7;
          description = ''
            How many timestamped dump files to keep locally in `dumpDir` (restic
            holds the longer history per its own retention). Older local dumps are
            pruned after each run.
          '';
        };

        # ── PITR (pgBackRest → R2) ────────────────────────────────────────────
        # Continuous WAL archiving + periodic base backups for point-in-time
        # recovery. Drops RPO from ~24h (logical dumps) to ~seconds ON A SINGLE
        # NODE — survives a full machine wipe with near-zero loss. This is the
        # durability the system-of-record (e.g. Forgejo) needs; the logical dumps
        # above stay on as an independent, cross-PG-major fallback.
        #
        # NOT streaming replication — that's a separate availability/HA project
        # (a second postgres on another host). PITR is single-node recoverability.
        pitr = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Enable pgBackRest WAL archiving + base backups to an S3/R2 repo.
              Sets archive_mode + wal_level, wires the archive_command, and adds a
              base-backup timer. Requires `environmentFile` (R2 creds) and a
              one-time `pgbackrest-stanza-create` (run declaratively on activation).
            '';
          };

          stanza = lib.mkOption {
            type = lib.types.str;
            default = "main";
            description = "pgBackRest stanza name (logical backup-config identifier).";
          };

          environmentFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = "/run/agenix/pgbackrest-r2-env";
            description = ''
              agenix env file exporting the pgBackRest S3/R2 secrets as
              PGBACKREST_* env vars (so they never enter the nix store):
                PGBACKREST_REPO1_S3_KEY=...
                PGBACKREST_REPO1_S3_KEY_SECRET=...
              Sourced into postgresql.service (so the archive_command sees it) and
              the base-backup/stanza units. null = wire it yourself.
            '';
          };

          s3 = {
            bucket = lib.mkOption {
              type = lib.types.str;
              default = "straylight-pg-pitr";
              description = "Dedicated R2 bucket for the WAL+base-backup repo.";
            };
            endpoint = lib.mkOption {
              type = lib.types.str;
              example = "6063b6652178f5cf1cfb87e7e41acf1e.r2.cloudflarestorage.com";
              default = "6063b6652178f5cf1cfb87e7e41acf1e.r2.cloudflarestorage.com";
              description = "R2 S3 endpoint host (account-scoped). Non-secret.";
            };
            region = lib.mkOption {
              type = lib.types.str;
              default = "auto";
              description = "S3 region (R2 = auto).";
            };
            bundle = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Bundle small files into combined objects (fewer R2 ops; cheaper).";
            };
          };

          baseBackup = {
            onCalendar = lib.mkOption {
              type = lib.types.str;
              default = "daily";
              description = "Timer for the differential base backup.";
            };
            fullOnCalendar = lib.mkOption {
              type = lib.types.str;
              default = "Sun *-*-* 02:00:00";
              description = "Timer for a full base backup (weekly anchor for the WAL chain).";
            };
          };

          retention = {
            full = lib.mkOption {
              type = lib.types.int;
              default = 4;
              description = "Number of full backups to retain (repo1-retention-full).";
            };
          };
        };
      };
    };

    redis.enable = lib.mkEnableOption "Redis server (off by default)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.postgres.enable {
      services.postgresql = {
        enable = true;
        inherit (cfg.postgres) package ensureDatabases ensureUsers;

        # When tailnet access is enabled, listen on ALL addresses (enableTCPIP is
        # the blessed NixOS knob → listen_addresses = "*"). Exposure is gated by
        # (a) the firewall opening 5432 only on tailscale0 and (b) pg_hba below
        # restricting md5 auth to loopback + the tailnet CIDRs. listen_addresses
        # takes addresses (not interface names), so binding the specific tailscale
        # IP isn't possible declaratively; "*" + firewall + pg_hba is the pattern.
        enableTCPIP = cfg.postgres.tailnet.enable;

        settings = cfg.postgres.settings;

        # Authentication: local peer for admin; md5 over the tailnet for clients.
        authentication = lib.mkIf cfg.postgres.tailnet.enable (
          lib.mkForce (
            ''
              # ── hyper-modern-nixos: tailnet-scoped access ──
              # TYPE  DATABASE  USER  ADDRESS            METHOD
              local   all       all                      peer
              host    all       all   127.0.0.1/32       md5
              host    all       all   ::1/128            md5
            ''
            + lib.concatMapStringsSep "\n" (
              cidr: "host    all       all   ${cidr}        md5"
            ) cfg.postgres.tailnet.cidrs
            + "\n"
          )
        );
      };

      # Open 5432 ONLY on the tailscale interface (layer 1). This bites only if
      # the host's firewall is enabled — watchtower opts back in.
      networking.firewall.interfaces.${cfg.postgres.tailnet.interface} =
        lib.mkIf cfg.postgres.tailnet.enable
          { allowedTCPPorts = [ 5432 ]; };

      # Grant the postgres user read access to each referenced secret, so the
      # postgres-run oneshot below can source it — purely declarative, no manual
      # chown. Root-owned, postgres group, 0440. atticd reads the same file via
      # systemd EnvironmentFile (as root) so this doesn't affect it. Only emitted
      # when rolePasswords is non-empty (so a host without agenix — e.g. a VM
      # test — that doesn't use rolePasswords never touches the age option).
      age.secrets = lib.mkIf (cfg.postgres.rolePasswords != { }) (
        lib.mapAttrs' (
          _role: spec:
          lib.nameValuePair spec.secret {
            group = "postgres";
            mode = "0440";
          }
        ) cfg.postgres.rolePasswords
      );

      # Declaratively set role passwords from agenix secrets, after postgres is
      # up. Idempotent ALTER ROLE; runs as the postgres superuser via peer auth.
      # The password is sourced at runtime (never the store).
      systemd.services.postgresql-role-passwords = lib.mkIf (cfg.postgres.rolePasswords != { }) {
        description = "set postgres role passwords from agenix secrets";
        after = [ "postgresql.service" ];
        requires = [ "postgresql.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          RemainAfterExit = true;
        };
        script = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            role: spec:
            let
              pgbin = "${config.services.postgresql.package}/bin/psql";
              envFile = "/run/agenix/${spec.secret}";
              # the literal shell var reference, e.g. $PGPASSWORD
              varRef = "$" + spec.var;
            in
            ''
              if [ -r "${envFile}" ]; then
                # shellcheck disable=SC1090
                pw=$( set -a; . "${envFile}"; printf '%s' "${varRef}" )
                if [ -n "$pw" ]; then
                  ${pgbin} -v ON_ERROR_STOP=1 \
                    -c "ALTER ROLE \"${role}\" WITH LOGIN PASSWORD '$pw';" \
                    || echo "warning: failed to set password for role ${role}" >&2
                else
                  echo "warning: ${spec.var} empty in ${envFile} for role ${role}" >&2
                fi
              else
                echo "warning: secret ${envFile} for role ${role} not readable" >&2
              fi
            ''
          ) cfg.postgres.rolePasswords
        );
      };
    })

    # ── Logical dumps → authoritative state (restic backs them up) ──────────────
    (lib.mkIf (cfg.postgres.enable && cfg.postgres.backup.enable) (
      let
        bcfg = cfg.postgres.backup;
        pgPkg = config.services.postgresql.package;
      in
      {
        # Classify the dump dir as authoritative: persisted across an
        # impermanence reboot AND backed up to R2 (via state.nix → backup.nix).
        hyper-modern-nixos.state.dirs.postgres-dumps = {
          path = bcfg.dumpDir;
          class = "authoritative";
        };

        # Create the dump dir owned by postgres (the dump runs as that user).
        systemd.tmpfiles.rules = [ "d ${bcfg.dumpDir} 0700 postgres postgres - -" ];

        # pg_dumpall (roles + all DBs) → timestamped zstd file. Logical dump is
        # the CORRECT restic source: consistent, restorable, version-portable.
        systemd.services.postgres-dump = {
          description = "logical pg_dumpall → ${bcfg.dumpDir} (zstd)";
          after = [ "postgresql.service" ];
          requires = [ "postgresql.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
          };
          path = [
            pgPkg
            pkgs.zstd
            pkgs.coreutils
            pkgs.findutils
          ];
          script = ''
            set -euo pipefail
            ts=$(date -u +%Y%m%dT%H%M%SZ)
            out="${bcfg.dumpDir}/pg_dumpall-$ts.sql.zst"
            tmp="$out.partial"
            # pg_dumpall over the local peer-auth socket (no password needed).
            pg_dumpall --clean --if-exists | zstd -q -19 -T0 -o "$tmp"
            mv "$tmp" "$out"
            # Prune to the most recent `keep` local dumps (restic keeps history).
            ls -1t "${bcfg.dumpDir}"/pg_dumpall-*.sql.zst 2>/dev/null \
              | tail -n +$((${toString bcfg.keep} + 1)) \
              | xargs -r rm -f --
            echo "// pg-dump // wrote $out"
          '';
        };

        systemd.timers.postgres-dump = {
          description = "schedule logical postgres dumps";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = bcfg.onCalendar;
            Persistent = true;
            RandomizedDelaySec = "10m";
          };
        };
      }
    ))

    # ── PITR: pgBackRest WAL archiving + base backups → R2 ──────────────────────
    (lib.mkIf (cfg.postgres.enable && cfg.postgres.backup.pitr.enable) (
      let
        p = cfg.postgres.backup.pitr;
        pgDataDir = config.services.postgresql.dataDir;
        pgbackrest = "${pkgs.pgbackrest}/bin/pgbackrest";
        stanzaArg = "--stanza=${p.stanza}";
        # Non-secret pgBackRest config. The S3 KEY/KEY_SECRET are NOT here — they
        # arrive as PGBACKREST_* env vars from the agenix environmentFile, so no
        # credential ever enters the nix store.
        confFile = pkgs.writeText "pgbackrest.conf" ''
          [global]
          repo1-type=s3
          repo1-s3-bucket=${p.s3.bucket}
          repo1-s3-endpoint=${p.s3.endpoint}
          repo1-s3-region=${p.s3.region}
          repo1-s3-uri-style=path
          repo1-retention-full=${toString p.retention.full}
          repo1-bundle=${if p.s3.bundle then "y" else "n"}
          # Compress in transit/at rest; modest level (CPU vs R2 storage, ~free).
          compress-type=zst
          compress-level=6
          process-max=4
          start-fast=y

          [${p.stanza}]
          pg1-path=${pgDataDir}
        '';
      in
      {
        assertions = [
          {
            assertion = p.environmentFile != null;
            message = ''
              postgres.backup.pitr.enable is true but pitr.environmentFile is null.
              pgBackRest needs the R2 S3 secrets (PGBACKREST_REPO1_S3_KEY[_SECRET])
              from an agenix env file — never the nix store. Wire it (default
              /run/agenix/pgbackrest-r2-env) or set environmentFile yourself.
            '';
          }
        ];

        # Self-wire the agenix secret (the .age lives in the repo). Root-owned
        # but postgres-group-readable (0440) so the daemon, the forked
        # archive_command, and the backup/stanza oneshots can all read the creds.
        age.secrets.pgbackrest-r2-env = {
          file = machineSecrets + "/pgbackrest-r2-env.age";
          group = "postgres";
          mode = "0440";
        };

        environment.etc."pgbackrest/pgbackrest.conf".source = confFile;
        environment.systemPackages = [ pkgs.pgbackrest ];

        # PITR requires WAL set up for archiving. mkForce-free merge: these are
        # added to whatever else is in settings.
        services.postgresql.settings = {
          archive_mode = "on";
          # pgBackRest pushes each completed segment to R2. %p = path, %f = file.
          archive_command = "${pgbackrest} ${stanzaArg} archive-push %p";
          wal_level = "replica";
          max_wal_senders = 3;
          archive_timeout = 60; # force a segment at least every 60s (bounds RPO)
        };

        # Feed the R2 secrets into postgresql.service so the archive_command
        # (a postgres subprocess) inherits PGBACKREST_* from the daemon env.
        # CRITICAL ordering: the agenix secret must be decrypted BEFORE postgres
        # starts, and postgres must RESTART if the secret changes — otherwise the
        # postmaster comes up without creds and archiving silently fails until a
        # manual restart. agenix runs as `${p.stanza}`-independent activation; we
        # bind to its unit + restart-trigger on the (runtime) secret path.
        systemd.services.postgresql = {
          serviceConfig.EnvironmentFile = p.environmentFile;
          after = [ "run-agenix.d.mount" ] ++ lib.optional config.services.openssh.enable "agenix.service";
          # Re-exec the postmaster when the decrypted env changes so it always
          # has live creds for the archive_command.
          restartTriggers = [ p.environmentFile ];
        };

        # pgBackRest wants its log dir to exist; create it for the postgres user.
        systemd.tmpfiles.rules = [
          "d /var/log/pgbackrest 0750 postgres postgres - -"
          "d /var/lib/pgbackrest 0750 postgres postgres - -"
        ];

        # One-time, idempotent stanza-create (like restic-init). Safe to re-run:
        # pgBackRest treats an existing stanza as success. Ordered after postgres.
        systemd.services.pgbackrest-stanza-create = {
          description = "pgBackRest one-time stanza-create for ${p.stanza}";
          after = [ "postgresql.service" ];
          requires = [ "postgresql.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            RemainAfterExit = true;
            EnvironmentFile = p.environmentFile;
          };
          script = ''
            ${pgbackrest} ${stanzaArg} stanza-create || \
              ${pgbackrest} ${stanzaArg} stanza-upgrade || true
            ${pgbackrest} ${stanzaArg} check
          '';
        };

        # Base backups: a weekly full (anchors the WAL chain) + a daily diff.
        # WAL archiving (continuous, via archive_command) is what gives ~seconds
        # RPO; base backups bound restore time + let old WAL be expired.
        systemd.services.pgbackrest-backup-diff = {
          description = "pgBackRest differential base backup";
          after = [ "postgresql.service" ];
          requires = [ "postgresql.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            EnvironmentFile = p.environmentFile;
            ExecStart = "${pgbackrest} ${stanzaArg} --type=diff backup";
          };
        };
        systemd.services.pgbackrest-backup-full = {
          description = "pgBackRest full base backup";
          after = [ "postgresql.service" ];
          requires = [ "postgresql.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            EnvironmentFile = p.environmentFile;
            ExecStart = "${pgbackrest} ${stanzaArg} --type=full backup";
          };
        };

        systemd.timers.pgbackrest-backup-diff = {
          description = "schedule pgBackRest differential backups";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = p.baseBackup.onCalendar;
            Persistent = true;
            RandomizedDelaySec = "10m";
          };
        };
        systemd.timers.pgbackrest-backup-full = {
          description = "schedule pgBackRest full backups";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = p.baseBackup.fullOnCalendar;
            Persistent = true;
            RandomizedDelaySec = "10m";
          };
        };
      }
    ))

    (lib.mkIf cfg.redis.enable { services.redis.servers."".enable = true; })
  ];
}
