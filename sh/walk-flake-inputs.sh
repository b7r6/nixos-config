#!/usr/bin/env bash
# collect-flake-options.sh - Simple and direct approach to collect all option definitions

set -e

# Find the nearest flake.nix by traversing up the directory tree
find_flake_root() {
  local dir="$1"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/flake.nix" ]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# Start from current directory if no argument is provided
START_DIR="${1:-.}"

# Find the flake root
FLAKE_DIR=$(find_flake_root "$(realpath "$START_DIR")")

if [ -z "$FLAKE_DIR" ]; then
  echo "Error: Could not find flake.nix in current directory or any parent directory!"
  echo "Please run this script from within a Nix flake directory structure."
  exit 1
fi

echo "Collecting option definitions from flake at: $FLAKE_DIR"

# Change to the flake directory
cd "$FLAKE_DIR"

# Create the nixd config directory
mkdir -p "$HOME/.config/nixd"

# Create basic structure
cat >"$HOME/.config/nixd/nixd.json" <<EOF
{
  "nixpkgs": {
    "path": "flake:nixpkgs"
  },
  "options": {
EOF

# Counter for option sets
OPTION_COUNT=0

# Function to add an option entry
add_option() {
  local name="$1"
  local expr="$2"

  # Sanitize the name
  name=$(echo "$name" | tr './' '-')

  # Add comma if not the first option
  if [ "$OPTION_COUNT" -gt 0 ]; then
    echo "," >>"$HOME/.config/nixd/nixd.json"
  fi

  # Append to the file
  echo "    \"$name\": {" >>"$HOME/.config/nixd/nixd.json"
  echo "      \"expr\": \"$expr\"" >>"$HOME/.config/nixd/nixd.json"
  echo -n "    }" >>"$HOME/.config/nixd/nixd.json"

  # Increment counter
  OPTION_COUNT=$((OPTION_COUNT + 1))

  echo "  Added option set: $name"
}

# Add core options
echo "Adding core options..."
add_option "nixos" "let
        lib = import (builtins.getFlake 'flake:nixpkgs').outPath + \"/lib\";
        modules = import (builtins.getFlake 'flake:nixpkgs').outPath + \"/nixos/modules\";
        args = {
          inherit lib;
          pkgs = { };
          name = \\\"unknown-host\\\";
          config = { };
          specialArgs = { };
        };
      in
        (lib.evalModules {
          inherit (args) pkgs;
          specialArgs = args.specialArgs;
          modules = [ modules ];
        }).options"

add_option "home-manager" 'let hmFlake = builtins.getFlake \"github:nix-community/home-manager\"; in hmFlake.options'
add_option "flake-parts" 'let fpFlake = builtins.getFlake \"github:hercules-ci/flake-parts\"; in fpFlake.options or {}'

# Check for flake-parts debug module
echo "Checking for flake-parts debug module..."
if nix --quiet eval --expr 'builtins.hasAttr "debug" (builtins.getFlake (toString ./.)) && builtins.hasAttr "options" ((builtins.getFlake (toString ./.))).debug' --impure 2>/dev/null | grep -q "true"; then
  echo "Found flake-parts debug module!"
  add_option "flake-parts-debug" "let flake = builtins.getFlake '${FLAKE_DIR}'; in flake.debug.options"
fi

# Check for NixOS configurations
echo "Checking for NixOS configurations..."
HOSTNAME=$(hostname)
if nix --quiet eval --expr "builtins.hasAttr \"nixosConfigurations\" (builtins.getFlake (toString ./.)) && builtins.hasAttr \"$HOSTNAME\" ((builtins.getFlake (toString ./.))).nixosConfigurations" --impure 2>/dev/null | grep -q "true"; then
  echo "Found NixOS configuration for $HOSTNAME"
  add_option "nixos-${HOSTNAME}" "let flake = builtins.getFlake '${FLAKE_DIR}'; in flake.nixosConfigurations.${HOSTNAME}.options"
fi

# Check for any other NixOS configurations
if nix --quiet eval --expr 'builtins.hasAttr "nixosConfigurations" (builtins.getFlake (toString ./.)))' --impure 2>/dev/null | grep -q "true"; then
  CONFIG_NAMES=$(nix --quiet eval --expr "builtins.attrNames (builtins.getFlake (toString ./.).nixosConfigurations)" --impure --json 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")

  for config in $CONFIG_NAMES; do
    # Skip hostname we already added
    if [ "$config" != "$HOSTNAME" ]; then
      echo "Found NixOS configuration: $config"
      add_option "nixos-${config}" "let flake = builtins.getFlake '${FLAKE_DIR}'; in flake.nixosConfigurations.${config}.options"
    fi
  done
fi

# Look for home-manager configurations
echo "Looking for home-manager configurations..."
if nix --quiet eval --expr 'builtins.hasAttr "homeConfigurations" (builtins.getFlake (toString ./.)))' --impure 2>/dev/null | grep -q "true"; then
  CONFIG_NAMES=$(nix --quiet eval --expr "builtins.attrNames (builtins.getFlake (toString ./.).homeConfigurations)" --impure --json 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")

  for config in $CONFIG_NAMES; do
    echo "Found home-manager configuration: $config"
    add_option "home-${config}" "let flake = builtins.getFlake '${FLAKE_DIR}'; in flake.homeConfigurations.\\\"${config}\\\".options"
  done
fi

# Process important flake inputs
echo "Getting flake inputs..."
INPUTS=$(nix --quiet flake metadata --json | jq -r '.locks.nodes | keys[]')

# Function to process a module in an input
process_module() {
  local input_name="$1"
  local input_ref="$2"
  local module_type="$3"
  local module_name="$4"

  # Try to instantiate the module
  # We do this with a simple Nix expression to test if we can get options from it
  local has_options
  has_options=$(nix --quiet eval --expr "
        let
            inputFlake = builtins.getFlake \"$input_ref\";
            module = inputFlake.$module_type.$module_name;
            dummyArgs = { config = {}; lib = (builtins.getFlake \"flake:nixpkgs\").lib; pkgs = {}; };
            result = builtins.tryEval (
                if builtins.isFunction module then module dummyArgs else module
            );
        in
            result.success && builtins.isAttrs result.value && builtins.hasAttr \"options\" result.value
    " --impure 2>/dev/null)

  if [ "$has_options" = "true" ]; then
    echo "    Module has options: $module_name"
    add_option "input-${input_name}-${module_type}-${module_name}" "let inputFlake = builtins.getFlake \\\"$input_ref\\\"; in (inputFlake.${module_type}.${module_name} { config = {}; lib = (builtins.getFlake \\\"flake:nixpkgs\\\").lib; pkgs = {}; }).options or {}"
  fi
}

# Process each input for NixOS and home-manager modules
echo "Processing flake inputs..."

for input in $INPUTS; do
  echo "Checking input: $input"

  # Get the input's reference
  INPUT_PATH=$(nix --quiet flake metadata --json | jq -r ".locks.nodes.\"$input\".locked.path" 2>/dev/null || echo "null")
  INPUT_URL=$(nix --quiet flake metadata --json | jq -r ".locks.nodes.\"$input\".locked.url" 2>/dev/null || echo "null")

  # Skip if we can't determine a reference
  if [[ $INPUT_PATH == "null" && $INPUT_URL == "null" ]]; then
    continue
  fi

  # Use path if available, otherwise use URL
  if [[ $INPUT_PATH != "null" ]]; then
    FLAKE_REF="$INPUT_PATH"
  else
    # Convert GitHub URLs to flake refs
    if [[ $INPUT_URL == *"github.com"* ]]; then
      OWNER=$(echo "$INPUT_URL" | sed -E 's|https://github.com/([^/]+)/([^/]+).*|\1|')
      REPO=$(echo "$INPUT_URL" | sed -E 's|https://github.com/([^/]+)/([^/]+).*|\2|')
      REV=$(nix --quiet flake metadata --json | jq -r ".locks.nodes.\"$input\".locked.rev" 2>/dev/null || echo "")

      if [ -n "$REV" ]; then
        FLAKE_REF="github:$OWNER/$REPO/$REV"
      else
        FLAKE_REF="github:$OWNER/$REPO"
      fi
    else
      FLAKE_REF="$INPUT_URL"
    fi
  fi

  # Check for top-level options
  if nix --quiet eval --expr "builtins.hasAttr \"options\" (builtins.getFlake \"$FLAKE_REF\")" --impure 2>/dev/null | grep -q "true"; then
    echo "  Found top-level options"
    add_option "input-${input}-options" "let inputFlake = builtins.getFlake \\\"$FLAKE_REF\\\"; in inputFlake.options"
  fi

  # Check for NixOS modules
  if nix --quiet eval --expr "builtins.hasAttr \"nixosModules\" (builtins.getFlake \"$FLAKE_REF\")" --impure 2>/dev/null | grep -q "true"; then
    echo "  Found nixosModules"

    # Get module names
    MODULE_NAMES=$(nix --quiet eval --expr "builtins.attrNames (builtins.getFlake \"$FLAKE_REF\").nixosModules" --impure --json 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")

    for module in $MODULE_NAMES; do
      echo "  Processing nixosModule: $module"
      process_module "$input" "$FLAKE_REF" "nixosModules" "$module"
    done
  fi

  # Check for home-manager modules
  for hmModPath in "hmModules" "homeManagerModules"; do
    if nix --quiet eval --expr "builtins.hasAttr \"$hmModPath\" (builtins.getFlake \"$FLAKE_REF\")" --impure 2>/dev/null | grep -q "true"; then
      echo "  Found $hmModPath"

      # Get module names
      MODULE_NAMES=$(nix --quiet eval --expr "builtins.attrNames (builtins.getFlake \"$FLAKE_REF\").${hmModPath}" --impure --json 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")

      for module in $MODULE_NAMES; do
        echo "  Processing $hmModPath: $module"
        process_module "$input" "$FLAKE_REF" "$hmModPath" "$module"
      done
    fi
  done
done

# Complete the options section
echo "" >>"$HOME/.config/nixd/nixd.json"
echo "  }," >>"$HOME/.config/nixd/nixd.json"

# Complete the configuration
cat >>"$HOME/.config/nixd/nixd.json" <<EOF
  "formatting": {
    "command": "nixfmt"
  },
  "eval": {
    "workers": 4,
    "depth": 10,
    "timeout": 10,
    "trace": false,
    "flake": {
      "registries": [
        {
          "type": "indirect",
          "path": "${FLAKE_DIR}/flake.lock"
        }
      ]
    }
  }
}
EOF

echo "Done! Option definitions collected from the flake and its inputs."
echo "Configuration file created at: $HOME/.config/nixd/nixd.json"
echo "Total option sets found: $OPTION_COUNT"
