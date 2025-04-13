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

  programs.bash.initExtra = lib.mkIf (config.programs.bash.enable) ''
    # Setup LLM tool with API keys from .netrc
    function setup_ai_env() {
      # Anthropic API key
      export ANTHROPIC_API_KEY=$(${readNetrcEntry "api.anthropic.com"})

      # OpenAI API key
      export OPENAI_API_KEY=$(${readNetrcEntry "api.openai.com"})

      # GitHub Copilot API key
      export GITHUB_TOKEN=$(${readNetrcEntry "github.com"})

      # DeepSeek API key
      export DEEPSEEK_API_KEY=$(${readNetrcEntry "api.deepseek.com"})

      # Configure LLM tool
      export LLM_ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY

      # Set environment variables for gptel (Emacs)
      # These are picked up by gptel automatically
      export GPTEL_API_KEY=$OPENAI_API_KEY  # For OpenAI
      export GPTEL_ANTHROPIC_KEY=$ANTHROPIC_API_KEY  # For Anthropic

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
