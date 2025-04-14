# Visual Studio Code configuration for the ProArt P16
{ config, lib, pkgs, ... }:

{
  options.vscode = {
    enable = lib.mkEnableOption "Enable Visual Studio Code with custom configuration";
  };

  config = lib.mkIf config.vscode.enable {
    programs.vscode = {
      enable = true;
      
      # Use open-source version
      package = pkgs.vscodium;
      
      # Basic settings
      enableUpdateCheck = false;
      enableExtensionUpdateCheck = false;
      
      # Extensions
      extensions = with pkgs.vscode-extensions; [
        # Theme & UI
        vscodevim.vim                     # Vim emulation
        usernamehw.errorlens              # Better error highlighting
        oderwat.indent-rainbow            # Colorize indentation
        pkief.material-icon-theme         # Better icons
        
        # Language support
        bbenoist.nix                      # Nix language
        jnoortheen.nix-ide                # Enhanced Nix support
        redhat.vscode-yaml                # YAML support
        tamasfe.even-better-toml          # TOML support
        
        # JavaScript/TypeScript
        dbaeumer.vscode-eslint            # ESLint
        esbenp.prettier-vscode            # Prettier
        bradlc.vscode-tailwindcss         # TailwindCSS support
        
        # Python
        ms-python.python                  # Python
        ms-python.vscode-pylance          # Python language server
        
        # C/C++
        llvm-vs-code-extensions.vscode-clangd  # Clangd
        
        # Rust
        rust-lang.rust-analyzer           # Rust
        tamasfe.even-better-toml          # TOML for Cargo.toml
        
        # Docker & Kubernetes
        ms-azuretools.vscode-docker       # Docker
        
        # Git
        eamodio.gitlens                   # Git supercharged
        
        # Productivity
        github.copilot                    # AI coding assistant
        github.github-vscode-theme        # GitHub theme
        christian-kohler.path-intellisense # Path autocomplete
        
        # Markdown
        yzhang.markdown-all-in-one        # Markdown support
        bierner.markdown-preview-github-styles # GitHub markdown
      ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        # Additional extensions not in nixpkgs
        {
          name = "cursor-theme";
          publisher = "kamikillerto";
          version = "1.0.0";
          sha256 = "sha256-6JXxt/sBXzD8+G0c/R1QeTCASUZ0zK7MULs7GObAeUM=";
        }
        {
          name = "noctis";
          publisher = "liviuschera";
          version = "10.40.0";
          sha256 = "sha256-SZWQyyUtGyAdHXKdMmFdgoFFew5gZUts1CjKUKBe8fw=";
        }
        {
          name = "material-theme";
          publisher = "zhuangtongfa";
          version = "3.15.8";
          sha256 = "sha256-f85yt4olovpWmCJ6dVbFq23swKG7BNwFnvJM4lrQbpY=";
        }
      ];
      
      # User settings
      userSettings = {
        # Editor appearance
        "workbench.colorTheme" = "One Dark Pro Darker";
        "workbench.iconTheme" = "material-icon-theme";
        "editor.fontFamily" = "'Berkeley Mono SemiBold', 'Droid Sans Mono', 'monospace'";
        "editor.fontSize" = 14;
        "editor.fontLigatures" = true;
        "editor.lineHeight" = 22;
        "editor.minimap.enabled" = false;
        "editor.cursorStyle" = "block";
        "editor.cursorBlinking" = "solid";
        "editor.renderWhitespace" = "boundary";
        "editor.guides.indentation" = true;
        "editor.bracketPairColorization.enabled" = true;
        "workbench.editor.enablePreview" = false;
        "window.menuBarVisibility" = "toggle";
        "window.titleBarStyle" = "custom";
        
        # Editor behavior
        "editor.formatOnSave" = true;
        "editor.formatOnPaste" = true;
        "editor.linkedEditing" = true;
        "editor.tabSize" = 2;
        "editor.insertSpaces" = true;
        "editor.detectIndentation" = true;
        "editor.wordWrap" = "on";
        "editor.suggestSelection" = "first";
        "diffEditor.ignoreTrimWhitespace" = false;
        "files.insertFinalNewline" = true;
        "files.trimTrailingWhitespace" = true;
        
        # Vim plugin settings
        "vim.leader" = "<space>";
        "vim.hlsearch" = true;
        "vim.incsearch" = true;
        "vim.useSystemClipboard" = true;
        "vim.handleKeys" = {
          "<C-c>" = false;
          "<C-v>" = false;
          "<C-x>" = false;
          "<C-a>" = false;
          "<C-f>" = false;
        };
        "vim.normalModeKeyBindingsNonRecursive" = [
          { "before" = ["<leader>" "w"]; "commands" = [":w"]; }
          { "before" = ["<leader>" "q"]; "commands" = [":q"]; }
          { "before" = ["<leader>" "n"]; "commands" = [":nohl"]; }
        ];
        
        # Terminal
        "terminal.integrated.fontFamily" = "'Berkeley Mono SemiBold', 'monospace'";
        "terminal.integrated.fontSize" = 14;
        "terminal.integrated.cursorBlinking" = true;
        "terminal.integrated.gpuAcceleration" = "on";
        
        # Languages
        "[nix]" = {
          "editor.tabSize" = 2;
          "editor.defaultFormatter" = "jnoortheen.nix-ide";
        };
        "[javascript]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
        "[typescript]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
        "[json]" = {
          "editor.defaultFormatter" = "esbenp.prettier-vscode";
        };
        "[python]" = {
          "editor.tabSize" = 4;
          "editor.formatOnType" = true;
        };
        "[rust]" = {
          "editor.defaultFormatter" = "rust-lang.rust-analyzer";
        };
        "[markdown]" = {
          "editor.defaultFormatter" = "yzhang.markdown-all-in-one";
          "editor.wordWrap" = "on";
          "editor.quickSuggestions" = { "comments" = "on"; "strings" = "on"; "other" = "on"; };
        };
        
        # Telemetry
        "telemetry.telemetryLevel" = "off";
        "telemetry.enableCrashReporter" = false;
        "telemetry.enableTelemetry" = false;
        
        # Updates
        "update.mode" = "none";
        "extensions.autoUpdate" = false;
        "extensions.autoCheckUpdates" = false;
        
        # Performance
        "files.watcherExclude" = {
          "**/.git/objects/**" = true;
          "**/.git/subtree-cache/**" = true;
          "**/node_modules/**" = true;
          "**/env/**" = true;
          "**/venv/**" = true;
          "**/.direnv/**" = true;
          "**/result/**" = true;
          "**/result-*/**" = true;
        };
        "search.exclude" = {
          "**/node_modules" = true;
          "**/bower_components" = true;
          "**/*.code-search" = true;
          "**/env" = true;
          "**/venv" = true;
          "**/.direnv" = true;
          "**/result" = true;
          "**/result-*" = true;
        };
        
        # Git
        "git.autofetch" = true;
        "git.confirmSync" = false;
        "git.enableSmartCommit" = true;
        "gitlens.codeLens.enabled" = false;
        
        # GitHub Copilot
        "github.copilot.enable" = {
          "*" = true;
          "plaintext" = false;
          "markdown" = true;
          "scminput" = false;
        };
        
        # Language-specific settings
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nil";
        "python.formatting.provider" = "black";
        "python.linting.enabled" = true;
        "python.linting.flake8Enabled" = true;
        "python.analysis.typeCheckingMode" = "basic";
        "rust-analyzer.checkOnSave.command" = "clippy";
        "javascript.updateImportsOnFileMove.enabled" = "always";
        "typescript.updateImportsOnFileMove.enabled" = "always";
      };
      
      # Keybindings
      keybindings = [
        {
          key = "ctrl+tab";
          command = "workbench.action.nextEditor";
        }
        {
          key = "ctrl+shift+tab";
          command = "workbench.action.previousEditor";
        }
        {
          key = "alt+j";
          command = "editor.action.moveLinesDownAction";
          when = "editorTextFocus && !editorReadonly";
        }
        {
          key = "alt+k";
          command = "editor.action.moveLinesUpAction";
          when = "editorTextFocus && !editorReadonly";
        }
        {
          key = "ctrl+b";
          command = "workbench.action.toggleSidebarVisibility";
        }
        {
          key = "ctrl+j";
          command = "workbench.action.togglePanel";
        }
        {
          key = "ctrl+p";
          command = "workbench.action.quickOpen";
        }
        {
          key = "ctrl+shift+f";
          command = "workbench.action.findInFiles";
        }
        {
          key = "ctrl+shift+space";
          command = "editor.action.triggerParameterHints";
          when = "editorHasSignatureHelpProvider && editorTextFocus";
        }
      ];
    };
  };
} 