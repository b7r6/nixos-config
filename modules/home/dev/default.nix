{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hyper-modern-nixos.dev;
in
{
  imports = [ ./git.nix ];

  options.hyper-modern-nixos.dev = {
    enable = lib.mkEnableOption "development tools and environment";

    core.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable core development tools (cmake, gh, just, etc.)";
    };

    buck2.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable `buck2`";
    };

    python.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Python development tools";
    };

    ruby.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Ruby development tools";
    };

    purescript.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Purescript development tools";
    };

    typescript.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable TypeScript/JavaScript development tools";
    };

    systems.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable systems development tools (C/C++, Zig)";
    };

    shell.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable shell scripting tools";
    };

    dhall.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Dhall configuration language tools";
    };

    dotnet.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable .NET SDK";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.gh = {
      enable = true;

      settings = {
        editor = "nvim";
        git_protocol = "ssh";
        prompt = "enabled";
        copilot.enabled = true;
      };
    };

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    home.packages =
      with pkgs;
      lib.flatten [
        # Core development tools (always included when dev is enabled)
        (lib.optionals cfg.core.enable [
          alejandra
          cmake
          fd
          forgejo-cli
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
          sysz
          dos2unix
          wget
          yazi
        ])

        # `buck2 development
        (lib.optionals cfg.python.enable [ buck2 ])

        # Python development
        # NB: do NOT add a bare `python312` here — the llm module installs
        # `python312.withPackages(...)`, and two python3 closures in one profile
        # collide on bin/2to3 etc. Use `uv` for project interpreters; basedpyright
        # bundles its own runtime.
        (lib.optionals cfg.python.enable [
          basedpyright # superset of pyright, no need for both
          ruff
          uv
        ])

        # Ruby development
        (lib.optionals cfg.ruby.enable [
          rubocop
          ruby_3_1
          solargraph
        ])

        # TypeScript/JavaScript development
        (lib.optionals cfg.typescript.enable [
          spago
          purescript
        ])

        # TypeScript/JavaScript development
        (lib.optionals cfg.typescript.enable [
          biome
          bun
          typescript
          fixjson
          nodejs
          prettier
          typescript
          typescript-language-server
        ])

        # Systems development (C/C++, Zig)
        (lib.optionals cfg.systems.enable [
          llvmPackages_22.clang-tools
          gcc
          gnumake
          zig
          zls
        ])

        # Shell scripting tools
        (lib.optionals cfg.shell.enable [
          bash-completion
          bash-language-server
          beautysh
          shellcheck
          shfmt
        ])

        # Dhall configuration language
        (lib.optionals cfg.dhall.enable [
          dhall
          dhall-bash
          dhall-docs
          dhall-json
          dhall-lsp-server
          dhall-nix
          dhall-yaml
        ])

        # .NET SDK
        (lib.optional cfg.dotnet.enable dotnet-sdk_9)
      ];
  };
}
