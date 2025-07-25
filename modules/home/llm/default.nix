{
  config,
  lib,
  pkgs,
  ...
}:
let
  readNetrcEntry = domain: ''
    if [ -f "$HOME/.netrc" ]; then
      grep -A 2 "machine ${domain}" "$HOME/.netrc" | grep "password" | awk '{print $2}'
    fi
  '';
in
{
  age = {
    secrets = {
      netrc = {
        file = ../../../secrets/b7r6/.netrc.age;
        path = "${config.home.homeDirectory}/.netrc";
        mode = "600";
      };
    };
  };

  home.packages = with pkgs; [
    (python313.withPackages (ps: [
      ps.llm
      ps.llm-anthropic
      ps.typing-extensions
      ps.setuptools
    ]))

    claude-code
  ];

  home.file.".llmrc".text = ''
    [settings]
    default_model = claude-3-sonnet-20240229
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

  programs.bash.initExtra = lib.mkIf config.programs.bash.enable ''
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

      # Enable Claude Code autocompletion
      if command -v claude-code &> /dev/null; then
        eval "$(claude-code completion bash)"
      fi
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
  '';
}
