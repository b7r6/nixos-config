# Cursor Rules

This directory contains rules for the AI assistant to follow when working with this codebase.

## Rule Structure

Each rule file should follow this format:

```
---
description: Brief description of the rule's purpose
globs: ["pattern/to/match/*.ext"] # Files this rule applies to
alwaysApply: true|false # Whether to apply automatically
priority: 100 # Higher numbers take precedence
---

# Rule Content
```

## Available Rules

| Rule File | Description | Priority |
|-----------|-------------|----------|
| diagnosis-rules.mdc | Rules for properly diagnosing issues in the codebase | 110 |
| flake-parts-rules.mdc | Rules for working with flake-parts modules | 95 |
| interaction-rules.mdc | Rules for ending interactions with users | 120 |
| nix-rules.mdc | Core rules for working with Nix | 100 |
| proto-rules.mdc | Rules for working with Protocol Buffers | 90 |

## Detailed Documentation

For more comprehensive documentation, see the following files:

- `nix_development_rules.md` - Detailed Nix development guidelines
- `proto_generator_rules.md` - Protocol buffer generator implementation rules
- `flake_parts_rules.md` - Comprehensive flake-parts module guidelines
- `flakes_guide.md` - General guide for working with Nix flakes
- `mcp_tools_guide.md` - Guide for using MCP tools effectively 