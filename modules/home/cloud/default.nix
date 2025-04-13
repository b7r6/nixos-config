{ pkgs, lib, ... }:
{
  options.cloud = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable cloud development tools";
    };
  };

  config.home.packages = with pkgs; [
    awscli2
    bash-my-aws

    # <<<<<<< Updated upstream:modules/home/cloud/default.nix
    #     bitwarden-cli
    #     bitwarden-desktop
    #     bws
    # =======

    google-cloud-sdk
    hclfmt
    hclfmt
    hcp
    terraform
    terraform-docs
    terraform-ls
    vault

    # TODO[b7r6]: fix the `terragrunt` derivation
    # terragrunt
  ];
}
