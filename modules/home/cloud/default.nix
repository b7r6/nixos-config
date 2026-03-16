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
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      with pkgs;
      lib.flatten [
        (lib.optional cfg.flyctl.enable flyctl)
        (lib.optional cfg.aws.enable awscli2)
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
  };
}
