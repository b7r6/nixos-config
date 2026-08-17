# `// hyprland // config`

A minimal, keyboard-driven Hyprland configuration with zero rounded corners, vim-style navigation,
and efficient workspace management.

## Design Philosophy

- **Zero border radius** - Clean, sharp corners throughout
- **Minimal gaps** - Just 2px for maximum screen real estate
- **Keyboard-first** - Everything accessible without reaching for the mouse
- **Vim-style navigation** - Consistent H/J/K/L movement patterns
- **Flat design** - No unnecessary visual flourishes

## Key Bindings

### Core Operations

| Binding | Action | | --------------------------- | --------------------------- | |
`Super + Return` | Open terminal (wezterm) | | `Super + Space` | Application launcher (wofi) | |
`Super + W` | Open web browser (firefox) | | `Super + E` | Open file manager (nemo) | |
`Super + BackSpace` | Close active window | | `Super + Shift + BackSpace` | Exit Hyprland |

### Window Management

#### Focus Navigation (Vim-style)

| Binding | Action | | ----------- | ----------- | | `Super + H` | Focus left | | `Super + J` |
Focus down | | `Super + K` | Focus up | | `Super + L` | Focus right |

#### Window Movement

| Binding | Action | | ------------------- | ----------------- | | `Super + Shift + H` | Move window
left | | `Super + Shift + J` | Move window down | | `Super + Shift + K` | Move window up | |
`Super + Shift + L` | Move window right |

#### Window Resizing

| Binding | Action | | ----------------- | -------------------- | | `Super + Alt + H` | Resize left
(-20px) | | `Super + Alt + J` | Resize down (+20px) | | `Super + Alt + K` | Resize up (-20px) | |
`Super + Alt + L` | Resize right (+20px) |

### Layout Controls (hy3)

| Binding | Action | | ------------------- | --------------------------- | | `Super + V` | Create
vertical split | | `Super + B` | Create horizontal split | | `Super + T` | Create tabbed group | |
`Super + G` | Toggle tab bar visibility | | `Super + R` | Raise window focus in group | |
`Super + Shift + G` | Switch to opposite layout |

### Window States

| Binding | Action | | ------------------- | -------------------------------------- | | `Super + F`
| Toggle fullscreen (maintain gaps) | | `Super + Shift + F` | Toggle fullscreen (no gaps) | |
`Super + D` | Toggle floating | | `Super + P` | Pin window (visible on all workspaces) |

### Workspace Navigation

#### Direct Access

| Binding | Action | | ------------------------- | ----------------------------- | |
`Super + [1-9,0]` | Switch to workspace 1-10 | | `Super + Shift + [1-9,0]` | Move window to
workspace 1-10 |

#### Cycling

| Binding | Action | | --------------------------- | ------------------------------------- | |
`Super + Tab` | Next workspace on current monitor | | `Super + Shift + Tab` | Previous workspace on
current monitor | | `Super + Alt + Tab` | Next workspace (global) | | `Super + Alt + Shift + Tab` |
Previous workspace (global) |

### Monitor Management

| Binding | Action | | ------------------- | ---------------------------------- | | `Super + ,` |
Focus previous monitor | | `Super + .` | Focus next monitor | | `Super + Shift + ,` | Move workspace
to previous monitor | | `Super + Shift + .` | Move workspace to next monitor |

### Special Workspace (Scratchpad)

| Binding | Action | | ------------------- | ------------------------- | | `Super + S` | Toggle
scratchpad | | `Super + Shift + S` | Move window to scratchpad |

The scratchpad automatically spawns a terminal if empty.

### Screenshots

| Binding | Action | | ----------------------------- | ------------------------------------------ |
| `Super + Print` | Screenshot region (copy to clipboard) | | `Super + Shift + Print` | Screenshot
region (save to file) | | `Super + Alt + Print` | Screenshot full screen (copy to clipboard) | |
`Super + Alt + Shift + Print` | Screenshot full screen (save to file) |

### Media & System Controls

| Binding | Action | | ----------------------- | --------------------- | | `XF86AudioRaiseVolume` |
Volume up (+5%) | | `XF86AudioLowerVolume` | Volume down (-5%) | | `XF86AudioMute` | Toggle mute | |
`XF86AudioPlay` | Play/pause media | | `XF86AudioNext` | Next track | | `XF86AudioPrev` | Previous
track | | `XF86MonBrightnessUp` | Brightness up (+5%) | | `XF86MonBrightnessDown` | Brightness down
(-5%) |

## Workspace Layout

Workspaces are persistent and monitor-aware:

- Workspaces 1-6 are assigned to the primary monitor (laptop)
- Additional monitors can be configured with their own workspace sets
- Workspaces persist even when empty

## UI Components

### Waybar

- Minimal top bar with essential information
- Left: Workspaces, active window title
- Center: Clock (click to toggle date)
- Right: CPU, Memory, Battery, Network, Volume, System tray

### Notifications (Mako)

- Clean, flat design with 1px borders
- Low/Normal urgency: Blue borders, 5s timeout
- High urgency: Red borders, no timeout

### Application Launcher (Wofi)

- Simple search interface
- No rounded corners
- Keyboard-driven selection

## Tips & Tricks

1. **Quick workspace switching**: Use `Super + Tab` to quickly cycle through workspaces on your
   current monitor

2. **Efficient layouts**: The hy3 plugin automatically tiles windows. Use `Super + V/B` to control
   split direction

3. **Scratchpad usage**: Keep frequently used apps in the scratchpad for quick access with
   `Super + S`

4. **Mouse usage**: While keyboard-focused, you can still:

   - `Super + Left Click`: Move windows
   - `Super + Right Click`: Resize windows

5. **Emergency exit**: If something goes wrong, `Super + Shift + BackSpace` will exit Hyprland

## Troubleshooting

- **Windows not tiling**: Ensure hy3 autotile is working. Some windows may have minimum size
  requirements
- **Keybindings not working**: Check if another application is capturing the keys first
- **Performance issues**: Try disabling blur or reducing animation speed in the config
