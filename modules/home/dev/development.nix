{ flake
, pkgs
, ...
}:
let
  inherit (flake) inputs;
in
{
  home.packages = with pkgs; [
    alejandra
    cmake
    fd
    gh
    git
    git-lfs
    gnumake
    jq
    just
    mdbook
    mdformat
    ninja
    openssl
    openssl.dev
    pkg-config
    ruff
    rustfmt
    shellcheck
    shfmt
    taplo
    toml-sort
    tree-sitter
    treefmt
    yamlfmt
    yq-go

    graphite-cli

    # sorted/categorized
    sysz
    dos2unix
    wget
    yazi

    # we're going to try out dhall...
    dhall
    dhall-bash
    dhall-docs
    dhall-json
    dhall-lsp-server
    dhall-nix
    dhall-yaml

    dotnet-sdk_9
  ];

  programs.gh = {
    enable = true;

    settings = {
      editor = "nvim";
      git_protocol = "ssh";
      prompt = "enabled";

      copilot = {
        enabled = true;
      };
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
