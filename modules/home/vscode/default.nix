# hyper-modern-nixos.vscode
#
# Prereq (one line in your flake): add the nix-vscode-extensions overlay so the
# long-tail extensions resolve with maintained hashes and you never hand-curate
# another sha256 again:
#
#   inputs.nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
#   # then in your nixpkgs/home-manager config:
#   nixpkgs.overlays = [ inputs.nix-vscode-extensions.overlays.default ];
#
# That exposes pkgs.vscode-marketplace.<publisher>.<name> and pkgs.open-vsx.<...>.
# Stable extensions stay on the nixpkgs `vscode-extensions` set; everything else
# comes from `vscode-marketplace` below.
#
# NOTE on Cursor: `programs.vscode` only manages *VS Code*. `pkgs.code-cursor`
# reads ~/.config/Cursor/User/{settings,keybindings}.json and its own extensions
# dir — none of the userSettings/keybindings/extensions here apply to it. If
# Cursor is your daily driver, you need a parallel home.file block targeting that
# path (or drop cursor.enable and commit to VS Code). Flagged, not solved.
{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.hyper-modern-nixos.vscode;
  marketplace = pkgs.vscode-marketplace;
in
{
  options.hyper-modern-nixos.vscode = {
    enable = lib.mkEnableOption "VS Code editor configuration";

    cursor.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Cursor (VS Code fork with AI). NOT configured by this module — see header note.";
    };

    stylix.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Stylix theme integration for VS Code";
    };

    font = {
      family = lib.mkOption {
        type = lib.types.str;
        default = "Berkeley Mono";
        description = "Font family for VS Code";
      };
      size = lib.mkOption {
        type = lib.types.int;
        default = 14;
        description = "Font size for VS Code";
      };
    };

    pythonChecker = lib.mkOption {
      type = lib.types.enum [
        "pyrefly"
        "ty"
      ];
      default = "pyrefly";
      description = ''
        Fast Python type checker / LSP for gigantic codebases.
        - pyrefly (Meta, 1.0 stable): runs on Instagram ~20M LOC + PyTorch/JAX,
          ~90% typing-spec conformance. The "proven at NVIDIA scale" pick.
        - ty (Astral, beta): lowest in-editor latency (~4.7ms incremental recompute
          on the PyTorch repo), lower conformance. Pick if keystroke latency is the
          dominant pain and you tolerate beta.
        Either way Pylance is disabled (python.languageServer = None) so the slow
        path is gone and ruff handles lint/format.
      '';
    };

    claudeCode.bypassPermissions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Skip all permission prompts (still has hard circuit breakers like rm -rf /).
        Two levers, both set: ~/.claude/settings.json defaultMode = bypassPermissions
        (shared by CLI + extension) AND the VS Code setting
        claudeCode.initialPermissionMode = bypassPermissions, which is the one the
        extension actually honors for new sessions. Appropriate given Firecracker
        isolation. Restart VS Code after first activation so the extension reloads.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    stylix.targets.vscode.enable = cfg.stylix.enable;
    stylix.targets.vscode.profileNames = [ "default" ];

    # Editor-critical servers that should resolve even outside a devshell.
    # Everything language-specific (clang, rustc, lean, purs/spago, nvcc, buck2,
    # python, ghc/dhall) comes from per-project nix-direnv — do NOT install those
    # globally, it fights the whole model. These are the cheap always-on fallbacks.
    home.packages = [
      pkgs.nixd
      pkgs.nixfmt
      pkgs.dhall-lsp-server
      # pkgs.clang-tools # clangd fallback when a project has no devshell yet
    ]
    ++ lib.optional cfg.cursor.enable pkgs.code-cursor;

    programs.vscode = {
      enable = true;
      package = pkgs.vscode-fhs;

      profiles.default.extensions =
        with pkgs.vscode-extensions;
        [
          # --- stable, from nixpkgs (no hashes to maintain) ---
          jnoortheen.nix-ide # nixd client
          mkhl.direnv # THE linchpin: loads .envrc env so every LSP inherits the nix toolchain
          llvm-vs-code-extensions.vscode-clangd # C++23 + CUDA host code
          rust-lang.rust-analyzer # Rust
          charliermarsh.ruff # Python lint/format (Rust, fast)
          tamasfe.even-better-toml
          ionide.ionide-fsharp
          ms-dotnettools.csharp
          ms-dotnettools.csdevkit
          ms-dotnettools.vscodeintellicode-csharp
          ms-python.python # interpreter select / test / debug glue only
          ms-python.debugpy
        ]
        # --- long tail, from the nix-vscode-extensions overlay (no hashes) ---
        ++ (with marketplace; [
          leanprover.lean4 # Lean 4
          nwolverson.language-purescript # PureScript syntax
          nwolverson.ide-purescript # PureScript LSP (purescript-language-server)
          dhall.dhall-lang # Dhall syntax
          dhall.vscode-dhall-lsp-server # Dhall LSP client (server = pkgs.dhall-lsp-server)
          nvidia.nsight-vscode-edition # CUDA debugging (cuda-gdb)
          anthropic.claude-code # Claude Code
          kilocode.kilo-code # agentic assistant + Codestral FIM autocomplete (Kilo gateway)
        ])
        # --- Python checker: pick one ---
        ++ lib.optional (cfg.pythonChecker == "pyrefly") marketplace.meta.pyrefly
        ++ lib.optional (cfg.pythonChecker == "ty") marketplace.astral-sh.ty;

      # Keep the 42crunch / dotnet marketplace pins you already had; these are the
      # ones you hand-hashed. (Migrate them to `marketplace.*` to drop the hashes.)
      profiles.default.userSettings = {
        # ---- Nix ----
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";

        "nix.serverSettings".nixd = {
          formatting.command = [ "nixfmt" ];
          # Fill these with YOUR flake exprs for option completion:
          # nixpkgs.expr = "import (builtins.getFlake \"/home/b7r6/cfg\").inputs.nixpkgs {}";
          # options.home-manager.expr = "(builtins.getFlake \"...\").homeConfigurations.b7r6.options";
        };

        # ---- direnv: keep LSPs alive across env changes ----
        "direnv.restart.automatic" = true;

        # ---- C++23 / CUDA host (clangd authoritative; needs compile_commands.json) ----
        "clangd.path" = "clangd"; # resolves from direnv PATH, NOT a bundled download
        "clangd.checkUpdates" = false;
        "clangd.onConfigChanged" = "restart";
        "clangd.arguments" = [
          "--background-index"
          "--clang-tidy"
          "--header-insertion=never"
          "--compile-commands-dir=." # buck2/cmake should emit compile_commands.json at root
          "--completion-style=detailed"
        ];
        "C_Cpp.intelliSenseEngine" = "disabled"; # no-op unless MS cpptools sneaks in; prevents clobbering clangd

        # ---- Rust (use nix/direnv binary, not the bundled download) ----
        "rust-analyzer.server.path" = "rust-analyzer";

        # buck2: set per-project in .vscode/settings.json, NOT globally:
        #   "rust-analyzer.linkedProjects": ["rust-project.json"]
        #   "rust-analyzer.cargo.buildScripts.enable": false
        # generate it with: buck2 bxl prelude//rust/rust-analyzer/check.bxl  (or your team's rust-project gen)

        # ---- Python: kill Pylance, fast checker + ruff ----
        "python.languageServer" = "None"; # disables Pylance — the slow path on huge repos
        "ruff.nativeServer" = "on";
        "[python]" = {
          "editor.defaultFormatter" = "charliermarsh.ruff";
          "editor.formatOnSave" = true;
          "editor.codeActionsOnSave"."source.organizeImports.ruff" = "explicit";
        };

        # ---- PureScript / Halogen (purs + spago from direnv) ----
        "purescript.addNpmPath" = false;
        "purescript.buildCommand" = "spago build --purs-args --json-errors";
        "purescript.formatter" = "purs-tidy";

        # ---- Lean 4 ----
        # Lean's elan-vs-nix toolchain tension is the fussiest of the set. If you
        # provide lean via nix (no elan), point the extension at it explicitly:
        #   "lean4.toolchainPath" = "${...lean from your devshell...}";
        # Otherwise leave default and let direnv put `lean` on PATH.

        # ---- Claude Code ----
        # initialPermissionMode is the lever the VS Code extension actually reads;
        # allowDangerouslySkipPermissions is the one it has historically ignored
        # (claude-code #12604/#29026/#34923/#42366). Set both, lead with the former.
        "claudeCode.initialPermissionMode" = lib.mkIf cfg.claudeCode.bypassPermissions "bypassPermissions";
        "claudeCode.allowDangerouslySkipPermissions" = lib.mkIf cfg.claudeCode.bypassPermissions true;

        # ---- FIM: Kilo Code (Codestral via Kilo gateway) ----
        # Autocomplete config lives in the extension UI, not settings.json: sign in
        # to Kilo, enable autocomplete (Codestral). No local-endpoint knobs here —
        # the gateway is cloud + billed, unlike the old continue.dev local setup.
        "kilo-code.autocomplete.enabled" = true;

        # ---- visual noise: gone ----
        "editor.minimap.enabled" = false; # the "miniview" insanity
        "editor.lineNumbers" = "off";
        "editor.guides.indentation" = false; # the vertical lines in the whitespace
        "editor.guides.highlightActiveIndentation" = false;
        "editor.guides.bracketPairs" = false;
        "editor.guides.bracketPairsHorizontal" = false;

        # ---- emacs-feel cursor: blinking block + hl-line ----
        "editor.cursorStyle" = "block";
        "editor.cursorBlinking" = "blink";
        "editor.renderLineHighlight" = "all"; # hl-line: full-width current-line highlight

        # ---- fonts (your existing block) ----
        "chat.editor.fontFamily" = lib.mkForce cfg.font.family;
        "chat.editor.fontSize" = lib.mkForce cfg.font.size;
        "debug.console.fontFamily" = lib.mkForce cfg.font.family;
        "debug.console.fontSize" = lib.mkForce cfg.font.size;
        "editor.fontFamily" = lib.mkForce cfg.font.family;
        "editor.fontSize" = lib.mkForce cfg.font.size;
        "editor.inlayHints.fontFamily" = lib.mkForce cfg.font.family;
        "editor.inlineSuggest.fontFamily" = lib.mkForce cfg.font.family;
        "markdown.preview.fontFamily" = lib.mkForce cfg.font.family;
        "markdown.preview.fontSize" = lib.mkForce cfg.font.size;
        "scm.inputFontFamily" = lib.mkForce cfg.font.family;
        "scm.inputFontSize" = lib.mkForce cfg.font.size;
        "terminal.integrated.fontSize" = lib.mkForce cfg.font.size;
      };

      # ---- keyboard: bounce editor<->terminal, toggle bars, all from the keys ----
      # ctrl+alt cluster deliberately avoids the C-x / C-b / C-c prefixes your emacs
      # extension claims, so nothing fights for the chord. Rebind to taste — the
      # command IDs are the point.
      profiles.default.keybindings = [
        # bounce focus: same key, complementary `when` clauses
        {
          key = "ctrl+alt+t";
          command = "workbench.action.terminal.focus";
          when = "editorTextFocus";
        }
        {
          key = "ctrl+alt+t";
          command = "workbench.action.focusActiveEditorGroup";
          when = "terminalFocus";
        }
        # visibility toggles
        {
          key = "ctrl+alt+b";
          command = "workbench.action.toggleSidebarVisibility";
        }
        {
          key = "ctrl+alt+]";
          command = "workbench.action.toggleAuxiliaryBar";
        } # right sidebar
        {
          key = "ctrl+alt+\\";
          command = "workbench.action.togglePanel";
        }
        {
          key = "ctrl+alt+0";
          command = "workbench.action.closeSidebar";
        }
        # window navigation (emacs other-window, but reaching every group)
        {
          key = "ctrl+alt+o";
          command = "workbench.action.focusNextGroup";
        }
        {
          key = "ctrl+alt+z";
          command = "workbench.action.toggleZenMode";
        }
        # migrated from the old hand-written ~/.config/Code/User/keybindings.json
        {
          key = "ctrl+x ctrl+p";
          command = "terminal.focus";
        } # emacs C-x prefix chord
        {
          key = "ctrl+g";
          command = "-workbench.action.gotoLine";
        } # free C-g for emacs keymap
      ];
    };

    # ---- Claude Code: berserk mode ----
    # ~/.claude/settings.json is CC-owned mutable state: CC writes its accumulated
    # allow-list, enabledPlugins, theme, effortLevel straight into it. A read-only
    # home.file symlink can't work (it both collides on activation and would wipe
    # that state + block future writes). So we MERGE, not own: jq sets just
    # .permissions.defaultMode each switch, preserving everything CC wrote.
    # defaultMode alone is what skips prompts (an allow=["*"] wildcard is not a
    # meaningful entry — allow is for granular per-command rules).
    home.activation.claudeBypassPermissions = lib.mkIf cfg.claudeCode.bypassPermissions (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        claudeSettings="''${HOME}/.claude/settings.json"
        run mkdir -p "$(dirname "$claudeSettings")"
        if [ -f "$claudeSettings" ]; then
          tmp="$(${pkgs.coreutils}/bin/mktemp)"
          ${pkgs.jq}/bin/jq '.permissions.defaultMode = "bypassPermissions"' \
            "$claudeSettings" > "$tmp" && run mv "$tmp" "$claudeSettings"
        else
          run echo '{"permissions":{"defaultMode":"bypassPermissions"}}' > "$claudeSettings"
        fi
      ''
    );
  };
}
