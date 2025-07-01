#!/usr/bin/env bash

# Get extensions
echo "programs.vscode = {"
echo "  enable = true;"
echo "  extensions = with pkgs.vscode-extensions; ["
code --list-extensions | while read extension; do
  echo "    # ${extension}"
done
echo "  ];"

# Get settings
echo "  userSettings = "
cat ~/.config/Code/User/settings.json
cat ./.vscode/settings.json
echo ";"
echo "};"
