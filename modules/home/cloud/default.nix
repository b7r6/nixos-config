{ pkgs, ... }:
{
  home.packages = with pkgs; [
    # <<<<<<< Updated upstream:modules/home/cloud/default.nix
    #     bitwarden-cli
    #     bitwarden-desktop
    #     bws
    # =======

    flyctl
    flycast
    awscli2
    bash-my-aws
    google-cloud-sdk
    hclfmt
    hcp
    terraform
    terraform-docs
    terraform-ls

    # TODO[b7r6]: very heavy and not in use, obviously make it a module option...
    # vault

    # TODO[b7r6]: fix the `terragrunt` derivation
    # terragrunt
  ];
}
