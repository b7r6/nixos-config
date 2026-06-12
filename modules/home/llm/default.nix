{ config
, lib
, pkgs
, ...
}:
let
  cfg = config.hyper-modern-nixos.llm;

  readNetrcEntry = domain: ''
    if [ -f "$HOME/.netrc" ]; then
      grep -A 2 "machine ${domain}" "$HOME/.netrc" | grep "password" | awk '{print $2}'
    fi
  '';

  # Shared shell initialization for both bash and zsh
  shellInit = ''
    # Setup LLM tool with API keys from .netrc
    function setup_ai_env() {
      # Check if netrc exists
      if [ ! -f "$HOME/.netrc" ]; then
        echo "Warning: .netrc file not found" >&2
        return 1
      fi

      # Anthropic API key
      export ANTHROPIC_API_KEY=$(${readNetrcEntry "api.anthropic.com"})

      # OpenAI API key
      export OPENAI_API_KEY=$(${readNetrcEntry "api.openai.com"})

      # Tailscale API key
      export TAILSCALE_API_KEY=$(${readNetrcEntry "api.tailscale.com"})

      # Buf.build API key
      export BUF_TOKEN=$(${readNetrcEntry "buf.build"})

      # Brave Search API key
      export BRAVE_SEARCH_API_KEY=$(${readNetrcEntry "search.brave.com"})

      # Latitude API key
      export LATITUDE_API_KEY=$(${readNetrcEntry "api.latitude.sh"})

      # Together AI API key
      export TOGETHER_API_KEY=$(${readNetrcEntry "api.together.xyz"})

      # OpenRouter API key
      export OPENROUTER_API_KEY=$(${readNetrcEntry "api.openrouter.ai"})

      # OpenRouter Provisioning API key
      export OPENROUTER_PROVISIONING_API_KEY=$(${readNetrcEntry "provisioning.openrouter.ai"})

      # Configure LLM tool
      export LLM_ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY

      # Set environment variables for gptel (Emacs)
      export GPTEL_API_KEY=$OPENAI_API_KEY
      export GPTEL_ANTHROPIC_KEY=$ANTHROPIC_API_KEY
    }

    # Only run if we're in an interactive shell
    if [[ $- == *i* ]]; then
      setup_ai_env >/dev/null 2>&1
    fi

    # Claude Code specific helpers
    cc_edit() {
      claude-code edit "$@"
    }

    cc_fix() {
      claude-code fix "$@"
    }

    cc_explain() {
      claude-code explain "$@"
    }

    # Aider helpers - uses OpenRouter via the fuck.yuou key
    ai() {
      # Get the working OpenRouter key from netrc
      local key
      key=$(grep -A 2 "machine fuck.yuou.openrouter.ai" "$HOME/.netrc" 2>/dev/null | grep "password" | awk '{print $2}')
      if [ -z "$key" ]; then
        echo "Error: No OpenRouter key found in .netrc (fuck.yuou.openrouter.ai)" >&2
        return 1
      fi
      OPENROUTER_API_KEY="$key" aider "$@"
    }

    # Quick aider with specific models
    ai-opus() {
      ai --model openrouter/anthropic/claude-opus-4 "$@"
    }

    ai-sonnet() {
      ai --model openrouter/anthropic/claude-sonnet-4 "$@"
    }

    ai-deepseek() {
      ai --model openrouter/deepseek/deepseek-r1 "$@"
    }

    ai-fast() {
      ai --model openrouter/anthropic/claude-3.5-haiku "$@"
    }

    # Architect mode: plan with big model, execute with fast model
    ai-architect() {
      ai --architect --model openrouter/anthropic/claude-opus-4 \
         --editor-model openrouter/anthropic/claude-sonnet-4 "$@"
    }
  '';
in
{
  options.hyper-modern-nixos.llm = {
    enable = lib.mkEnableOption "LLM tools and AI assistant integration";

    claude-code.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Claude Code CLI tool";
    };

    aider.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable aider AI pair programming tool";
    };

    llm-cli.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable llm CLI tool with various providers";
    };

    secrets.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable agenix-managed secrets for API keys";
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "claude-3-sonnet-20240229";
      description = "Default model for llm CLI";
    };
  };

  config = lib.mkIf cfg.enable {
    age.secrets = lib.mkIf cfg.secrets.enable {
      netrc = {
        file = ../../../secrets/agenix/users/b7r6/netrc.age;
        path = "${config.home.homeDirectory}/.netrc";
        mode = "600";
      };
    };

    home.packages =
      with pkgs;
      lib.flatten [
        (lib.optionals cfg.llm-cli.enable [
          (python312.withPackages (ps: [
            ps.llm
            ps.llm-anthropic
            ps.llm-deepseek
            ps.llm-openrouter
            ps.typing-extensions
            ps.setuptools
          ]))
        ])
        (lib.optional cfg.claude-code.enable claude-code)
        (lib.optional cfg.aider.enable aider-chat)
      ];

    # Aider configuration - uses OpenRouter by default
    home.file.".aider.conf.yml" = lib.mkIf cfg.aider.enable {
      text = ''
        # Aider configuration
        # https://aider.chat/docs/config/aider_conf.html

        # Use OpenRouter as the API provider
        openrouter: true

        # Default model (via OpenRouter)
        model: openrouter/anthropic/claude-sonnet-4

        # Editor model for diffs (faster/cheaper)
        editor-model: openrouter/anthropic/claude-sonnet-4

        # Git integration
        auto-commits: true
        dirty-commits: true
        attribute-author: false
        attribute-committer: false

        # UI preferences
        dark-mode: true
        pretty: true
        stream: true

        # Code style
        encoding: utf-8
        line-endings: lf

        # Don't watch files by default (explicit is better)
        watch-files: false

        # Repo map settings
        map-tokens: 2048
        map-refresh: auto
      '';
    };

    home.file.".llmrc" = lib.mkIf cfg.llm-cli.enable {
      text = ''
        [settings]
        default_model = ${cfg.defaultModel}
        save_history = true

        [models.claude-3-opus-20240229]
        model = claude-3-opus-20240229
        provider = anthropic

        [models.claude-3-sonnet-20240229]
        model = claude-3-sonnet-20240229
        provider = anthropic

        [models.claude-3-haiku-20240307]
        model = claude-3-haiku-20240307
        provider = anthropic

        [models.gpt-4o]
        model = gpt-4o
        provider = openai

        [models.gpt-4o-mini]
        model = gpt-4o-mini
        provider = openai

        [models.deepseek-chat]
        model = deepseek-chat
        provider = deepseek

        [models.olmo-7b]
        model = ollama/olmo:7b
        provider = ollama
        local = true
      '';
    };

    # Bash: shared shell init + bash-specific completions
    programs.bash.initExtra = lib.mkIf config.programs.bash.enable ''
      ${shellInit}

      # Bash-specific: Claude Code autocompletion
      if command -v claude-code &> /dev/null; then
        eval "$(claude-code completion bash)"
      fi
    '';

    # Zsh: shared shell init + zsh-specific completions
    programs.zsh.initContent = lib.mkIf config.programs.zsh.enable ''
      ${shellInit}

      # Zsh-specific: Claude Code autocompletion
      if command -v claude-code &> /dev/null; then
        eval "$(claude-code completion zsh)"
      fi
    '';
  };
}
