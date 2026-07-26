# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                             // hyper-modern-nixos // checks // vscode-config
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# The repo-homed declared layer (dotfiles/vscode/) feeds an activation-time jq
# merge, so a malformed file silently degrades to `{}` at switch time — this
# gate makes malformed loud instead. Beyond validity, it pins the NixOS
# story's contract: language servers are PATH-RESOLVED (bare binary names,
# never store paths or bundled downloads), so the same settings file works on
# any box where nix/direnv/the distro provides the server.
{ pkgs }:
pkgs.runCommand "vscode-config"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    settings=${../dotfiles/vscode/settings.json}
    keybindings=${../dotfiles/vscode/keybindings.json}

    jq -e 'type == "object"' "$settings" > /dev/null
    jq -e 'type == "array"' "$keybindings" > /dev/null

    # PATH-resolution contract: bare names, no slashes
    jq -e '."nix.serverPath" == "nixd"' "$settings" > /dev/null
    jq -e '."clangd.path" == "clangd"' "$settings" > /dev/null
    jq -e '."rust-analyzer.server.path" == "rust-analyzer"' "$settings" > /dev/null
    if jq -r 'to_entries[] | select(.key | test("serverPath|\\.path$")) | .value' \
        "$settings" | grep -q '/'; then
      echo "server path contains a slash — PATH resolution broken"; exit 1
    fi

    # every keybinding is {key, command}
    jq -e 'all(.[]; has("key") and has("command"))' "$keybindings" > /dev/null

    echo "vscode declared layer: valid, PATH-resolved"
    touch $out
  ''
