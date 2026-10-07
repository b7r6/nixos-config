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
{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  cfg = config.hyper-modern-nixos.vscode;
  marketplace = pkgs.vscode-marketplace;

  jsonFormat = pkgs.formats.json { };

  # ── Stylix theme as a self-installed extension ──────────────────────────────
  # We disable stylix.targets.vscode (it writes settings.json as a read-only
  # home.file symlink, which fights the LWW merge below and trips home-manager's
  # checkLinkTargets collision guard every switch). Instead we build the SAME
  # theme extension stylix would, from its own pinned template, and select it
  # via workbench.colorTheme in the merged userSettings. One writer for
  # settings.json (our activation), theme still applied.
  stylixColors = config.lib.stylix.colors;
  stylixThemeExtension =
    pkgs.runCommandLocal "stylix-vscode"
      {
        vscodeExtUniqueId = "stylix.stylix";
        vscodeExtPublisher = "stylix";
        version = "0.0.0";
        theme = builtins.toJSON (
          import "${flake.inputs.stylix}/modules/vscode/templates/theme.nix" stylixColors
        );
        passAsFile = [ "theme" ];
      }
      ''
        mkdir -p "$out/share/vscode/extensions/$vscodeExtUniqueId/themes"
        ln -s ${flake.inputs.stylix}/modules/vscode/package.json "$out/share/vscode/extensions/$vscodeExtUniqueId/package.json"
        cp "$themePath" "$out/share/vscode/extensions/$vscodeExtUniqueId/themes/stylix.json"
      '';

  # ── LWW JSON merge (the home-manager `programs.zed-editor` pattern) ──────────
  # home-manager's `programs.vscode` writes settings.json as a READ-ONLY nix
  # store symlink, so VS Code/Cursor can never persist a setting and the file
  # collides on activation. Zed's HM module solves the same problem with an
  # activation-time `jq` deep-merge into the MUTABLE file; we extend that shape
  # one layer: `$dynamic * $repo * $computed` — start from whatever the editor
  # wrote (dynamic), overlay the REPO-HOMED declared settings
  # (dotfiles/vscode/settings.json, read live from the working tree at
  # activation — edit them there, no rebuild), then the thin nix-computed
  # overlay (fonts, theme selection, option-conditional flags). Rightmost wins
  # on conflict. The target stays writable, so the editor keeps its own keys
  # and the declared layers are reasserted every switch.
  # Read current content as the dynamic baseline FIRST (works whether the path
  # is a writable file OR a read-only home-manager store symlink — e.g. the one
  # stylix.targets.vscode still writes), THEN drop a symlink / non-writable file
  # so the subsequent write lands a real, editor-writable file. Without the rm,
  # `printf >` follows the symlink into the read-only nix store and fails with
  # EACCES — that's the read-only-config bug this whole change fixes.
  repoSettingsPath = "${config.hyper-modern-nixos.dotfiles.path}/vscode/settings.json";
  repoKeybindingsPath = "${config.hyper-modern-nixos.dotfiles.path}/vscode/keybindings.json";

  lwwMergeSettings = path: computedFile: ''
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname ${lib.escapeShellArg path})"
    dynamic="$(${pkgs.jq}/bin/jq '.' ${lib.escapeShellArg path} 2>/dev/null || echo '{}')"
    repo="$(${pkgs.jq}/bin/jq '.' ${lib.escapeShellArg repoSettingsPath} 2>/dev/null || echo '{}')"
    if [ -L ${lib.escapeShellArg path} ] || { [ -e ${lib.escapeShellArg path} ] && [ ! -w ${lib.escapeShellArg path} ]; }; then
      ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg path}
    fi
    computed="$(${pkgs.coreutils}/bin/cat ${computedFile})"
    merged="$(${pkgs.jq}/bin/jq -n '$dynamic * $repo * $computed' \
      --argjson dynamic "$dynamic" --argjson repo "$repo" --argjson computed "$computed")"
    printf '%s\n' "$merged" > ${lib.escapeShellArg path}
    unset dynamic repo computed merged
  '';

  # Keybindings are a JSON ARRAY, not an object: LWW by `key`+`command` identity
  # so editor-added bindings survive and the repo-declared ones are reasserted.
  # Same read-then-replace-symlink dance as settings.
  lwwMergeKeybindings = path: ''
    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname ${lib.escapeShellArg path})"
    dynamic="$(${pkgs.jq}/bin/jq '.' ${lib.escapeShellArg path} 2>/dev/null || echo '[]')"
    repo="$(${pkgs.jq}/bin/jq '.' ${lib.escapeShellArg repoKeybindingsPath} 2>/dev/null || echo '[]')"
    if [ -L ${lib.escapeShellArg path} ] || { [ -e ${lib.escapeShellArg path} ] && [ ! -w ${lib.escapeShellArg path} ]; }; then
      ${pkgs.coreutils}/bin/rm -f ${lib.escapeShellArg path}
    fi
    merged="$(${pkgs.jq}/bin/jq -n \
      '($dynamic + $repo) | unique_by([.key, .command, (.when // "")])' \
      --argjson dynamic "$dynamic" --argjson repo "$repo")"
    printf '%s\n' "$merged" > ${lib.escapeShellArg path}
    unset dynamic repo merged
  '';

  # Everything DECLARED lives in dotfiles/vscode/{settings,keybindings}.json
  # (repo-homed, PATH-resolved server paths: nixd/clangd/rust-analyzer as bare
  # names — checks.vscode-config pins that contract). This overlay is only what
  # genuinely derives from nix options.
  computedSettings = {
    "chat.editor.fontFamily" = cfg.font.family;
    "chat.editor.fontSize" = cfg.font.size;
    "debug.console.fontFamily" = cfg.font.family;
    "debug.console.fontSize" = cfg.font.size;
    "editor.fontFamily" = cfg.font.family;
    "editor.fontSize" = cfg.font.size;
    "editor.inlayHints.fontFamily" = cfg.font.family;
    "editor.inlineSuggest.fontFamily" = cfg.font.family;
    "markdown.preview.fontFamily" = cfg.font.family;
    "markdown.preview.fontSize" = cfg.font.size;
    "scm.inputFontFamily" = cfg.font.family;
    "scm.inputFontSize" = cfg.font.size;
    "terminal.integrated.fontSize" = cfg.font.size;
  }
  # ---- stylix theme (extension installed below; select it here) ----
  // lib.optionalAttrs cfg.stylix.enable { "workbench.colorTheme" = "Stylix"; }
  # ---- Claude Code (only when bypass requested) ----
  # initialPermissionMode is the lever the VS Code extension actually reads;
  # allowDangerouslySkipPermissions is the one it has historically ignored
  # (claude-code #12604/#29026/#34923/#42366). Set both, lead with the former.
  // lib.optionalAttrs cfg.claudeCode.bypassPermissions {
    "claudeCode.initialPermissionMode" = "bypassPermissions";
    "claudeCode.allowDangerouslySkipPermissions" = true;
  };

  computedSettingsFile = jsonFormat.generate "vscode-computed-settings.json" computedSettings;

  # Editors whose user dirs we LWW-merge into. VS Code (Code/User) and Cursor
  # (Cursor/User) read the same settings.json/keybindings.json schema; the
  # store-symlink path could never reach Cursor at all, the merge does.
  editorUserDirs = [
    "${config.xdg.configHome}/Code/User"
  ]
  ++ lib.optional cfg.cursor.enable "${config.xdg.configHome}/Cursor/User";
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
    # Disabled deliberately: stylix's vscode target writes settings.json as a
    # read-only home.file symlink, which collides with our LWW merge (and trips
    # home-manager's checkLinkTargets every switch). We install its theme
    # extension ourselves (stylixThemeExtension) and set workbench.colorTheme in
    # the merged userSettings instead.
    stylix.targets.vscode.enable = false;

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
          tuttieee.emacs-mcx # Awesome Emacs Keymap (C-x C-s, kill ring, marks)
        ])
        # --- Python checker: pick one ---
        ++ lib.optional (cfg.pythonChecker == "pyrefly") marketplace.meta.pyrefly
        ++ lib.optional (cfg.pythonChecker == "ty") marketplace.astral-sh.ty
        # --- stylix theme (built from stylix's own pinned template) ---
        ++ lib.optional cfg.stylix.enable stylixThemeExtension;

      # All extensions above come from nixpkgs `vscode-extensions` or the
      # `nix-vscode-extensions` marketplace overlay — no hand-maintained hashes.
      #
      # NOTE: userSettings/keybindings are deliberately NOT set here.
      # home-manager's `programs.vscode` writes settings.json as a READ-ONLY nix
      # store symlink, so the editor can never persist a change and the file
      # collides on activation. Instead we LWW-merge them into the mutable files
      # below (home.activation.vscodeSettings/vscodeKeybindings), the same way
      # home-manager's `programs.zed-editor` handles its mutable config.
    };

    # ---- VS Code / Cursor: LWW-merge settings + keybindings into mutable files ----
    # The store-symlink approach (home-manager's programs.vscode) makes these
    # read-only and never reaches Cursor. Instead, on every activation we
    # jq-deep-merge our declared config into whatever the editor currently has,
    # leaving the files writable so the editor keeps persisting its own keys.
    # entryAfter linkGeneration (NOT writeBoundary): linkGeneration is itself
    # `entryAfter [ writeBoundary ]` and is what places the read-only store
    # symlink (stylix's settings.json). We must run strictly after it so we
    # replace that symlink with our merged writable file — same anchor the
    # programs.zed-editor module uses for the identical reason.
    home.activation.vscodeSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] (
      lib.concatMapStringsSep "\n" (
        dir: lwwMergeSettings "${dir}/settings.json" computedSettingsFile
      ) editorUserDirs
    );

    home.activation.vscodeKeybindings = lib.hm.dag.entryAfter [ "linkGeneration" ] (
      lib.concatMapStringsSep "\n" (dir: lwwMergeKeybindings "${dir}/keybindings.json") editorUserDirs
    );

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
