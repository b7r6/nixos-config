{ pkgs, ... }:
{
  home.packages = with pkgs; [
    flyctl
    awscli2
    # bash-my-aws
    google-cloud-sdk
    hclfmt
    hcp
    terraform
    terraform-docs
    terraform-ls
    # TODO[b7r6]: fix the `terragrunt` derivation
    # terragrunt
  ];
}
