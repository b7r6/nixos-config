# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                        // hyper-modern-nixos // home/session
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Session configuration: XDG dirs, environment, SSH, secrets management
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.session;
in
{
  options.hyper-modern-nixos.session = {
    enable = lib.mkEnableOption "session configuration and management";

    ssh.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable SSH client configuration";
    };

    ssh.autoAddKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        ".ssh/id_ed25519"
        ".ssh/id_ed25519_b7r6"
      ];
      description = ''
        Private key paths (relative to $HOME) to load into the ssh-agent at
        login via a systemd user service. Loaded regardless of session type
        (graphical, console, SSH) — wanted by default.target, not
        graphical-session.target. Missing keys are skipped silently; pass-
        phrased keys will fail to load unattended (use AddKeysToAgent for those).
      '';
    };

    secrets.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable secrets management tools (agenix, yubikey)";
    };

    secrets.repoPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/src/nixos-config";
      description = "Path to the nixos-config repository (for passage store)";
    };

    editor = lib.mkOption {
      type = lib.types.str;
      default = "nvim";
      description = "Default editor";
    };

    xdg.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable XDG base directory and user directory setup";
    };
  };

  config = lib.mkIf cfg.enable {
    # ── XDG Configuration ──────────────────────────────────────────────────────

    xdg = lib.mkIf cfg.xdg.enable {
      enable = true;

      # Create standard user directories
      userDirs = {
        enable = true;
        createDirectories = true;
        setSessionVariables = false;

        # Standard XDG directories
        desktop = "${config.home.homeDirectory}/Desktop";
        documents = "${config.home.homeDirectory}/Documents";
        download = "${config.home.homeDirectory}/Downloads";
        music = "${config.home.homeDirectory}/Music";
        pictures = "${config.home.homeDirectory}/Pictures";
        publicShare = "${config.home.homeDirectory}/Public";
        templates = "${config.home.homeDirectory}/Templates";
        videos = "${config.home.homeDirectory}/Videos";

        # Extra directories (non-standard but useful)
        extraConfig = {
          PROJECTS = "${config.home.homeDirectory}/src";
          SCREENSHOTS = "${config.home.homeDirectory}/Pictures/Screenshots";
        };
      };

      # MIME type associations
      mimeApps = {
        enable = true;

        defaultApplications = {
          # Web
          "text/html" = [ "firefox.desktop" ];
          "x-scheme-handler/http" = [ "firefox.desktop" ];
          "x-scheme-handler/https" = [ "firefox.desktop" ];
          "x-scheme-handler/about" = [ "firefox.desktop" ];
          "x-scheme-handler/unknown" = [ "firefox.desktop" ];

          # Email
          "x-scheme-handler/mailto" = [ "thunderbird.desktop" ];

          # Images
          "image/png" = [ "imv.desktop" ];
          "image/jpeg" = [ "imv.desktop" ];
          "image/gif" = [ "imv.desktop" ];
          "image/webp" = [ "imv.desktop" ];
          "image/svg+xml" = [ "imv.desktop" ];

          # Video
          "video/mp4" = [ "mpv.desktop" ];
          "video/webm" = [ "mpv.desktop" ];
          "video/x-matroska" = [ "mpv.desktop" ];

          # Audio
          "audio/mpeg" = [ "mpv.desktop" ];
          "audio/ogg" = [ "mpv.desktop" ];
          "audio/flac" = [ "mpv.desktop" ];

          # Documents
          "application/pdf" = [ "org.pwmt.zathura.desktop" ];
          "application/epub+zip" = [ "org.pwmt.zathura.desktop" ];

          # Text
          "text/plain" = [ "nvim.desktop" ];
          "text/x-shellscript" = [ "nvim.desktop" ];

          # Archives
          "application/zip" = [ "org.gnome.FileRoller.desktop" ];
          "application/x-tar" = [ "org.gnome.FileRoller.desktop" ];
          "application/gzip" = [ "org.gnome.FileRoller.desktop" ];

          # File manager
          "inode/directory" = [ "nemo.desktop" ];
        };
      };
    };

    # ── Session variables ──────────────────────────────────────────────────────

    home.sessionVariables = lib.mkMerge [
      {
        PATH = "$HOME/.local/bin:$PATH";
        EDITOR = cfg.editor;
        VISUAL = cfg.editor;
        NIXPKGS_ALLOW_UNFREE = "1";

        # n.b. deliberately NO SSH_AUTH_SOCK export here. The standard agent
        # (programs.ssh.startAgent in modules/nixos/base.nix) ships a properly
        # guarded export via environment.extraInit — it never clobbers the
        # forwarded socket sshd seeds on `ssh -A` sessions. An export in this
        # block is unguarded on every fleet host and has broken agent
        # forwarding twice (first for gcr-ssh-agent, since killed — the fleet
        # runs passphrase-less keys for agenix, so gcr bought nothing). Do
        # not reintroduce.

        # Pager
        PAGER = "less";
        LESS = "-R --mouse --wheel-lines=3";
        MANPAGER = "sh -c 'col -bx | bat -l man -p'";

        # History
        HISTSIZE = "50000";
        SAVEHIST = "50000";
      }
      (lib.mkIf cfg.secrets.enable {
        # Passage (age-based pass) - read directly from repo, no symlinks
        # This ensures secrets are accessible from any clone of the repo
        PASSAGE_DIR = "${cfg.secrets.repoPath}/secrets/passage-store";
        PASSAGE_IDENTITIES_FILE = "${config.home.homeDirectory}/.passage/identities";
      })
    ];

    # SSH configuration
    programs.ssh = lib.mkIf cfg.ssh.enable {
      enable = true;
      # Disable legacy default config to silence warning
      enableDefaultConfig = false;

      settings =
        let
          # ── Fleet host table: name -> { lan, ts } ────────────────────────────
          # Recorded so every node stays reachable by DIRECT LAN address even when
          # the tailnet is having trouble. `<host>` resolves to the LAN address
          # first; `<host>-ts` is the tailscale (100.x) fallback. Update lan when
          # a box's DHCP/static lease changes (run `ssh <host-ts> ip -4 addr`).
          # LAN addresses verified 2026-06-19 over the tailnet (192.168.40.0/24).
          fleet = {
            ultraviolence = {
              lan = "192.168.40.115";
              ts = "100.71.82.73";
            };
            gossamer = {
              lan = "192.168.40.120";
              ts = "100.110.55.28";
            };
            guccimane = {
              lan = "192.168.40.81";
              ts = "100.89.101.109";
            };
            watchtower = {
              lan = "192.168.40.98";
              ts = "100.122.228.122";
            };
            # Offline when recorded — LAN address unknown, so the primary alias
            # points at the tailscale IP until a LAN address is confirmed.
            shimmer = {
              lan = "100.116.42.95";
              ts = "100.116.42.95";
            };
            weyl = {
              lan = "100.111.80.81";
              ts = "100.111.80.81";
            };
          };

          # name  -> { HostName = lan; }   (direct LAN, survives tailnet outage)
          lanBlocks = lib.mapAttrs (_: h: { HostName = h.lan; }) fleet;
          # name-ts -> { HostName = ts; }  (explicit tailscale fallback)
          tsBlocks = lib.mapAttrs' (n: h: lib.nameValuePair "${n}-ts" { HostName = h.ts; }) fleet;
        in
        {
          "*" = {
            ForwardAgent = true;
            AddKeysToAgent = "yes";
            StrictHostKeyChecking = "accept-new";
          };
          "github.com" = {
            User = "git";
          };
        }
        // lanBlocks
        // tsBlocks;
    };

    # ── Auto-load SSH keys into the agent at login (any session type) ───────────
    # ssh-agent starts empty. AddKeysToAgent=yes only adds a key on first local
    # use — which is too late for agent FORWARDING (a remote host can only use
    # keys already loaded). This systemd USER service runs `ssh-add` for each
    # configured key once the user session is up — wanted by default.target
    # (NOT graphical-session.target), so it also applies to console / headless
    # / SSH logins. Idempotent: re-adding a loaded key is a no-op; missing
    # keys are skipped.
    systemd.user.services.ssh-add-keys = lib.mkIf (cfg.ssh.enable && cfg.ssh.autoAddKeys != [ ]) {
      Unit = {
        Description = "Load SSH keys into the agent";
        After = [ "ssh-agent.service" ];
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        # standard ssh-agent socket (programs.ssh.startAgent) — matches the
        # guarded export in environment.extraInit.
        Environment = "SSH_AUTH_SOCK=%t/ssh-agent";
        ExecStart = pkgs.writeShellScript "ssh-add-keys" (
          lib.concatMapStringsSep "\n" (
            key:
            let
              path = "${config.home.homeDirectory}/${key}";
            in
            # only add keys that exist; never fail the unit on a missing/locked key
            "[ -f ${lib.escapeShellArg path} ] && ${pkgs.openssh}/bin/ssh-add ${lib.escapeShellArg path} || true"
          ) cfg.ssh.autoAddKeys
        );
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Secrets management tools
    home.packages = lib.mkIf cfg.secrets.enable (
      with pkgs;
      [
        # age encryption
        age-plugin-yubikey
        rage
        ragenix

        # passage (age-based pass)
        passage

        # yubikey
        fido2-manage
        yubikey-manager
        yubikey-personalization
        yubioath-flutter

        # other
        _1password-cli
      ]
    );

    # Symlink rage as age (passage expects 'age' in PATH)
    home.file.".local/bin/age" = lib.mkIf cfg.secrets.enable { source = "${pkgs.rage}/bin/rage"; };

    # Passage identities - create file listing SSH keys that can decrypt
    # Uses both id_ed25519 and id_ed25519_b7r6 for flexibility
    home.activation.passageIdentities = lib.mkIf cfg.secrets.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.passage"
        : > "$HOME/.passage/identities"
        for key in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519_b7r6"; do
          if [ -f "$key" ]; then
            echo "$key" >> "$HOME/.passage/identities"
          fi
        done
      ''
    );
  };
}
