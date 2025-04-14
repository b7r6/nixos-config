# WezTerm configuration optimized for ASUS ProArt P16
{ config, lib, pkgs, ... }:

{
  options.programs.wezterm-proart = {
    enable = lib.mkEnableOption "Enable WezTerm terminal optimized for ProArt P16";
  };

  config = lib.mkIf config.programs.wezterm-proart.enable {
    # Enable the base WezTerm module
    programs.wezterm = {
      enable = true;
      enableZshIntegration = true;
      
      extraConfig = ''
        local wezterm = require 'wezterm'
        local config = {}
        
        -- Use GPU rendering for better performance on high-DPI displays
        config.front_end = "WebGpu"
        
        -- Optimize for NVIDIA+AMD hybrid GPU system in ProArt
        config.webgpu_preferred_adapter = function(adapters)
          -- Prefer discrete GPU when available
          for _, adapter in ipairs(adapters) do
            if adapter.device_type == "DiscreteGpu" then
              return adapter
            end
          end
          return adapters[1]
        end
        
        -- Font configuration - Berkeley Mono optimized for high-DPI
        config.font = wezterm.font {
          family = 'Berkeley Mono',
          harfbuzz_features = {'calt=1', 'liga=1'},
        }
        config.font_size = 13.0
        
        -- High-DPI configuration for ProArt P16's display
        config.dpi = 192.0
        config.freetype_load_target = "Light"
        config.freetype_render_target = "HorizontalLcd"
        
        -- Enable Wayland for better HiDPI support
        config.enable_wayland = true
        
        -- Window appearance settings
        config.window_decorations = "RESIZE"
        config.window_padding = {
          left = 2,
          right = 2,
          top = 0,
          bottom = 0,
        }
        
        -- Default colors - Catppuccin Mocha theme optimized for ProArt display
        config.color_scheme = 'Catppuccin Mocha'
        
        -- Performance optimizations
        config.animation_fps = 60
        config.max_fps = 120
        config.scrollback_lines = 10000
        config.cursor_blink_rate = 800
        
        -- Key bindings for convenient system controls
        config.keys = {
          -- GPU toggle (useful for NVIDIA Optimus)
          {
            key = 'g', 
            mods = 'CTRL|SHIFT',
            action = wezterm.action.SpawnCommandInNewWindow {
              args = {'nvidia-smi'},
            },
          },
          -- Tab management
          {
            key = 't',
            mods = 'CTRL',
            action = wezterm.action.SpawnTab 'CurrentPaneDomain',
          },
          -- Font size control
          {
            key = '=',
            mods = 'CTRL',
            action = wezterm.action.IncreaseFontSize,
          },
          {
            key = '-',
            mods = 'CTRL',
            action = wezterm.action.DecreaseFontSize,
          },
        }
        
        return config
      '';
    };
    
    # Add WezTerm to system packages
    home.packages = with pkgs; [
      wezterm
    ];
  };
} 