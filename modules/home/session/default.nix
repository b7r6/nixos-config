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

      settings = {
        "*" = {
          ForwardAgent = "yes";
          AddKeysToAgent = "yes";
          StrictHostKeyChecking = "accept-new";
        };
        "github.com" = {
          User = "git";
        };
      };
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
    home.file.".local/bin/age" = lib.mkIf cfg.secrets.enable {
      source = "${pkgs.rage}/bin/rage";
    };

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
