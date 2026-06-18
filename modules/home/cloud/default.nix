{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.cloud;
in
{
  options.hyper-modern-nixos.cloud = {
    enable = lib.mkEnableOption "cloud tools and infrastructure management";

    aws.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable AWS CLI and tools";
    };

    gcp.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Google Cloud SDK (heavy ~500MB, disabled by default)";
    };

    terraform.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Terraform and related tools (heavy, disabled by default)";
    };

    flyctl.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Fly.io CLI";
    };

    hashicorp.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable HashiCorp tools (HCP, etc.) - requires terraform";
    };

    rclone = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install rclone on the user PATH.";
      };

      # rclone.conf holds the R2 remote definition AND its Access Key /
      # Secret Access Key, so it can never live in the nix store. When this is
      # true we decrypt a user-scoped agenix secret (rclone-conf.age) STRAIGHT
      # to ~/.config/rclone/rclone.conf, mode 600 — same pattern as the netrc
      # secret in modules/home/llm. The secret's plaintext is a normal rclone
      # config, e.g.:
      #   [straylight-r2]
      #   type = s3
      #   provider = Cloudflare
      #   access_key_id = <R2 Access Key ID>
      #   secret_access_key = <R2 Secret Access Key>
      #   endpoint = https://<ACCOUNT_ID>.r2.cloudflarestorage.com
      #   acl = private
      config.enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.rclone.enable;
        description = "Deploy ~/.config/rclone/rclone.conf from the rclone-conf agenix secret (R2 remote + creds).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      with pkgs;
      lib.flatten [
        (lib.optional cfg.flyctl.enable flyctl)
        (lib.optional cfg.aws.enable awscli2)
        (lib.optional cfg.rclone.enable rclone)
        (lib.optionals cfg.gcp.enable [ google-cloud-sdk ])
        (lib.optionals cfg.terraform.enable [
          hclfmt
          terraform
          terraform-docs
          terraform-ls
          # TODO[b7r6]: fix the `terragrunt` derivation
          # terragrunt
        ])
        (lib.optional cfg.hashicorp.enable hcp)
      ];

    # Decrypt rclone.conf (R2 remote + creds) directly into the XDG path,
    # readable only by the user. agenix home-manager module owns the file.
    age.secrets = lib.mkIf cfg.rclone.config.enable {
      rclone-conf = {
        file = ../../../secrets/agenix/users/b7r6/rclone-conf.age;
        path = "${config.home.homeDirectory}/.config/rclone/rclone.conf";
        mode = "600";
      };
    };
  };
}
