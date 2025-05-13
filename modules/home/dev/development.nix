{ flake
, pkgs
, ...
}:
let
  inherit (flake) inputs;
in
{
  # TODO[b7r6]: most of these belong in one of the langauge toolchains...
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

    # TODO[b7r6]: this is a whole thing...
    dotnet-sdk_8

    # TODO[b7r6]: this is a whole thing...
    dotnet-sdk_8

    # TODO[b7r6]: this is a whole thing....
    inputs.devenv.packages."${pkgs.system}".devenv
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
