# Development Environments Flake Module
{ config, lib, ... }:

{
  # Define options for this flake module
  options.dev-environments = lib.mkOption {
    type = lib.types.submodule {
      options = {
        enable = lib.mkEnableOption "development environments";
      };
    };
    default = { enable = false; };
    description = "Development environments configuration";
  };

  # Implementation when enabled
  config = lib.mkIf config.dev-environments.enable {
    perSystem = { pkgs, system, ... }: {
      # Make development environments available
      dev-environments = {
        # Python development environment
        python = {
          description = "Python development environment";
          packages = with pkgs; [
            (python3.withPackages (ps: with ps; [
              pip setuptools wheel virtualenv
              black isort mypy pytest
            ]))
            poetry
            ruff
            basedpyright
            pyright
            uv
          ];
        };
          
        # Rust development environment
        rust = {
          description = "Rust development environment";
          packages = with pkgs; [
            rustup cargo rustc 
            rust-analyzer clippy rustfmt
          ];
        };
          
        # TypeScript development environment
        typescript = {
          description = "TypeScript development environment";
          packages = with pkgs; [
            nodejs_20
            nodePackages.npm
            nodePackages.typescript
            nodePackages.ts-node
            nodePackages.eslint
            nodePackages.prettier
          ];
        };
          
        # .NET development environment
        dotnet = {
          description = ".NET development environment";
          packages = with pkgs; [
            dotnet-sdk_8
          ];
        };
      };
    };
      
    # Define home-manager modules
    flake.homeManagerModules = {
      # Module with all development environments
      dev-environments = { pkgs, ... }: {
        home.packages = with pkgs; [
          # Python tools
          (python3.withPackages (ps: with ps; [
            pip setuptools wheel virtualenv
            black isort mypy pytest
          ]))
          poetry
          ruff
          basedpyright
          pyright
          uv
            
          # Rust tools
          rustup cargo rustc 
          rust-analyzer clippy rustfmt
            
          # TypeScript tools
          nodejs_20
          nodePackages.npm
          nodePackages.typescript
          nodePackages.ts-node
          nodePackages.eslint
          nodePackages.prettier
            
          # .NET tools
          dotnet-sdk_8
        ];
          
        # Configure editors when they're enabled
        programs.vscode = lib.mkIf (pkgs ? vscode-extensions) {
          extensions = with pkgs.vscode-extensions; [
            # Python
            ms-python.python
            ms-python.vscode-pylance
              
            # Rust
            rust-lang.rust-analyzer
            tamasfe.even-better-toml
              
            # TypeScript
            dbaeumer.vscode-eslint
            esbenp.prettier-vscode
              
            # .NET
            ms-dotnettools.csharp
          ];
        };
      };
        
      # Individual environment modules
      python-dev = { pkgs, ... }: {
        home.packages = with pkgs; [
          (python3.withPackages (ps: with ps; [
            pip setuptools wheel virtualenv
            black isort mypy pytest
          ]))
          poetry
          ruff
          basedpyright
          pyright
          uv
        ];
      };
      
      rust-dev = { pkgs, ... }: {
        home.packages = with pkgs; [
          rustup cargo rustc 
          rust-analyzer clippy rustfmt
        ];
      };
      
      typescript-dev = { pkgs, ... }: {
        home.packages = with pkgs; [
          nodejs_20
          nodePackages.npm
          nodePackages.typescript
          nodePackages.ts-node
          nodePackages.eslint
          nodePackages.prettier
        ];
      };
      
      dotnet-dev = { pkgs, ... }: {
        home.packages = with pkgs; [
          dotnet-sdk_8
        ];
      };
    };

    # Define NixOS modules for system-wide installation
    flake.nixosModules = {
      dev-environments = { pkgs, ... }: {
        environment.systemPackages = with pkgs; [
          # Python tools
          (python3.withPackages (ps: with ps; [
            pip setuptools wheel virtualenv
            black isort mypy pytest
          ]))
          poetry
          ruff
          basedpyright
          pyright
          uv
            
          # Rust tools
          rustup cargo rustc 
          rust-analyzer clippy rustfmt
            
          # TypeScript tools
          nodejs_20
          nodePackages.npm
          nodePackages.typescript
          nodePackages.ts-node
          nodePackages.eslint
          nodePackages.prettier
            
          # .NET tools
          dotnet-sdk_8
        ];
      };
    };
  };
}