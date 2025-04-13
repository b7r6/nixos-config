# NixOS Configuration Guide for Agents

## Build Commands
- `just update` - Update flake locks
- `just check` - Validate configuration
- `just lint` - Format nix files (using nixfmt)
- `just run` - Activate the configuration
- `just dev` - Enter development shell

## Code Style Guidelines
- **Nix Formatting**: Use nixfmt for consistent formatting (2-space indent)
- **Module Structure**: Keep modules organized by category (dev, shell, wayland, etc.)
- **Naming**: Use camelCase for Nix attributes and options
- **Types**: Define module options with proper types and descriptions
- **Imports**: Organize imports at the top, sorted alphabetically
- **Error Handling**: Use proper Nix error patterns (throw, abort, or assert)
- **Comments**: Document non-obvious configuration and options
- **Configuration**: Follow declarative patterns with enable flags

## Formatters
The repository uses treefmt with multiple language formatters:
- Nix: nixfmt
- TypeScript/JS/JSON: biome
- C/C++: clang-format
- Python: ruff
- Markdown: mdformat
- Ruby: rubocop
- Shell: shfmt + shellcheck