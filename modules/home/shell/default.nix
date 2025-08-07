#
# // hypermodern // shell
#
# "he'd always imagined it as a gradual and willing accommodation of
#  the machine, the parent organism. it was the root of street cool too,
#  the knowing posture that implied connection, invisible lines up to
#  hidden levels of influence."
#
{ config, lib, ... }:
with lib;
let
  cfg = config.hyper-modern-nixos.shell;

  # aesthetic presets for different shell personalities
  promptPresets = {
    # minimal cyberpunk aesthetic - clean lines, essential information
    matrix = "$username$hostname$directory$git_branch$git_state$git_status$cmd_duration$line_break$python$character";

    # maximum information density - for the data cowboys
    sprawl = "$all$character";

    # clean professional - for corporate infiltration
    corp = "$directory$git_branch$character";

    # custom aesthetic - user-defined hypermodern experience
    custom = cfg.starship.customFormat;
  };

  # intelligent shell aliases that surface workflow patterns
  intelligentAliases = {
    # git workflow shortcuts
    g = "git";
    gs = "git status";
    gd = "git diff";
    gc = "git commit";
    gp = "git push";
    gl = "git pull";

    # nix development workflow
    nr = "nix run";
    nd = "nix develop";
    nb = "nix build";
    nf = "nix flake";

    # directory navigation with cyberpunk flair
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";

    # process management for the modern operator
    k = "kill";
    ka = "killall";

    # file operations with safety
    rm = "rm -i";
    cp = "cp -i";
    mv = "mv -i";

    # enhanced listing for visual comprehension
    ll = "ls -la";
    la = "ls -A";
    l = "ls -CF";
    tree = "tree -C";
  };
in
{
  options.hyper-modern-nixos.shell = {
    enable = mkEnableOption "// hypermodern // shell" // {
      default = true;
    };

    aesthetic = {
      preset = mkOption {
        type = types.enum [
          "matrix"
          "sprawl"
          "corp"
          "custom"
        ];
        default = "matrix";
        description = ''
          Shell aesthetic preset:
          • matrix: minimal cyberpunk - essential information only
          • sprawl: maximum density - all available data streams  
          • corp: clean professional - corporate-safe appearance
          • custom: user-defined via customFormat option
        '';
      };

      enableIntelligentAliases = mkOption {
        type = types.bool;
        default = true;
        description = "Enable workflow-optimized command aliases for git, nix, and system operations";
      };
    };

    starship = {
      enable = mkEnableOption "starship prompt engine" // {
        default = true;
      };

      customFormat = mkOption {
        type = types.str;
        default = "$username$hostname$directory$git_branch$character";
        description = "Custom prompt format when aesthetic.preset is 'custom'";
        example = "$directory$git_branch$python$nodejs$rust$character";
      };

      showExecutionTime = mkOption {
        type = types.bool;
        default = true;
        description = "Display command execution time for performance awareness";
      };
    };

    atuin = {
      enable = mkEnableOption "atuin encrypted shell history" // {
        default = true;
      };

      syncAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Atuin sync server for cross-machine history synchronization";
        example = "https://api.atuin.sh";
      };

      keyPath = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to atuin encryption key for secure history storage";
        example = "/home/user/.config/atuin/key";
      };

      searchMode = mkOption {
        type = types.enum [
          "prefix"
          "fulltext"
          "fuzzy"
        ];
        default = "fuzzy";
        description = "History search algorithm for command retrieval";
      };
    };

    tmux = {
      enable = mkEnableOption "tmux session matrix" // {
        default = true;
      };

      prefix = mkOption {
        type = types.str;
        default = "C-o";
        description = "Tmux command prefix - your gateway to session control";
        example = "C-a";
      };

      philosophy = mkOption {
        type = types.enum [
          "emacs"
          "vi"
          "hybrid"
        ];
        default = "emacs";
        description = ''
          Navigation philosophy for tmux sessions:
          • emacs: fluid, immediate - for continuous thought flow
          • vi: modal, precise - for deliberate manipulation  
          • hybrid: context-aware - intelligent mode switching
        '';
      };

      mouse = mkOption {
        type = types.bool;
        default = true;
        description = "Enable mouse integration for seamless session navigation";
      };

      performance = {
        historyLimit = mkOption {
          type = types.int;
          default = 50000;
          description = "Scrollback buffer size - your digital memory depth";
        };

        escapeTime = mkOption {
          type = types.int;
          default = 0;
          description = "Key escape delay in milliseconds - optimize for responsiveness";
        };
      };

      aesthetic = {
        baseIndex = mkOption {
          type = types.int;
          default = 1;
          description = "Starting index for windows and panes (0-based or 1-based psychology)";
        };

        statusPosition = mkOption {
          type = types.enum [
            "top"
            "bottom"
            "off"
          ];
          default = "bottom";
          description = "Status bar placement for optimal information architecture";
        };
      };
    };

    workflow = {
      customAliases = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Personal workflow aliases - surface your unique command patterns";
        example = {
          deploy = "nix run .#deploy";
          test = "nix flake check";
          work = "cd ~/projects && tmux new-session -s work";
        };
      };

      extraPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Additional tools for your digital arsenal";
        example = literalExpression "with pkgs; [ ripgrep fd bat exa ]";
      };

      enableSystemIntegration = mkOption {
        type = types.bool;
        default = true;
        description = "Enable deep system integration for seamless workflow";
      };
    };
  };

  imports = [
    ./atuin.nix
    ./bash.nix
    ./cli.nix
    ./packages.nix
    ./shell.nix
    ./themed-shell.nix
    ./tmux.nix
  ];

  config = mkIf cfg.enable {
    # configure the starship prompt based on aesthetic preset
    hyper-modern-nixos.themed-shell = {
      enable = cfg.starship.enable || cfg.atuin.enable;
      starship = mkIf cfg.starship.enable { format = promptPresets.${cfg.aesthetic.preset}; };
      atuin = mkIf cfg.atuin.enable {
        inherit (cfg.atuin) syncAddress keyPath;
        # pass through the search mode preference and other settings
        settings = {
          search_mode = cfg.atuin.searchMode;
        };
      };
    };

    programs.tmux = mkIf cfg.tmux.enable {
      enable = true;
      inherit (cfg.tmux) prefix mouse;
      keyMode = cfg.tmux.philosophy;
      inherit (cfg.tmux.aesthetic) baseIndex;
      historyLimit = mkDefault cfg.tmux.performance.historyLimit;
      escapeTime = mkDefault cfg.tmux.performance.escapeTime;

      extraConfig =
        optionalString (cfg.tmux.aesthetic.statusPosition == "off") ''
          set -g status off
        ''
        + optionalString (cfg.tmux.aesthetic.statusPosition == "top") ''
          set -g status-position top
        '';
    };

    # intelligent alias system - merge user preferences with intelligent defaults
    home.shellAliases =
      (optionalAttrs cfg.aesthetic.enableIntelligentAliases intelligentAliases)
      // cfg.workflow.customAliases;

    # enhanced package environment for workflow optimization
    home.packages = cfg.workflow.extraPackages;

    # enable advanced shell integrations when requested
    programs.direnv.enable = mkDefault cfg.workflow.enableSystemIntegration;
    programs.zoxide.enable = mkDefault cfg.workflow.enableSystemIntegration;
  };
}
