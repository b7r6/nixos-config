# Firefox configuration for the ProArt P16
{ config, lib, pkgs, ... }:

{
  options.firefox = {
    enable = lib.mkEnableOption "Enable Firefox with custom configuration";
  };

  config = lib.mkIf config.firefox.enable {
    programs.firefox = {
      enable = true;
      
      # Use system-installed extensions
      package = pkgs.firefox;
      
      # Better wayland performance
      nativeMessagingHosts.packages = [
        pkgs.gnome-browser-connector
        pkgs.tridactyl-native
      ];
      
      profiles = {
        default = {
          id = 0;
          name = "default";
          isDefault = true;
          
          settings = {
            # Performance settings
            "gfx.webrender.all" = true;
            "media.ffmpeg.vaapi.enabled" = true;
            "media.hardware-video-decoding.force-enabled" = true;
            "widget.wayland-dmabuf-vaapi.enabled" = true;
            "browser.cache.disk.enable" = false;
            "browser.cache.memory.capacity" = 524288; # 512MB
            "browser.sessionstore.interval" = 60000; # 1 minute
            
            # Privacy settings
            "privacy.trackingprotection.enabled" = true;
            "privacy.trackingprotection.socialtracking.enabled" = true;
            "privacy.trackingprotection.cryptomining.enabled" = true;
            "privacy.trackingprotection.fingerprinting.enabled" = true;
            "privacy.donottrackheader.enabled" = true;
            "browser.contentblocking.category" = "strict";
            "network.cookie.cookieBehavior" = 5; # Reject trackers and partition third-party
            "browser.newtabpage.activity-stream.feeds.telemetry" = false;
            "browser.newtabpage.activity-stream.telemetry" = false;
            "browser.ping-centre.telemetry" = false;
            "toolkit.telemetry.archive.enabled" = false;
            "toolkit.telemetry.bhrPing.enabled" = false;
            "toolkit.telemetry.enabled" = false;
            "toolkit.telemetry.firstShutdownPing.enabled" = false;
            "toolkit.telemetry.hybridContent.enabled" = false;
            "toolkit.telemetry.newProfilePing.enabled" = false;
            "toolkit.telemetry.reportingpolicy.firstRun" = false;
            "toolkit.telemetry.shutdownPingSender.enabled" = false;
            "toolkit.telemetry.unified" = false;
            "toolkit.telemetry.updatePing.enabled" = false;
            
            # UI settings
            "browser.compactmode.show" = true;
            "browser.uidensity" = 1; # Compact mode
            "browser.tabs.loadBookmarksInTabs" = true;
            "browser.toolbars.bookmarks.visibility" = "always";
            "browser.search.suggest.enabled" = false;
            "browser.urlbar.suggest.searches" = false;
            
            # Behavior settings
            "browser.warnOnQuit" = false;
            "browser.tabs.warnOnClose" = false;
            "browser.tabs.closeWindowWithLastTab" = false;
            "browser.aboutConfig.showWarning" = false;
            "browser.shell.checkDefaultBrowser" = false;
            "browser.download.always_ask_before_handling_new_types" = true;
            
            # GPU acceleration
            "layers.acceleration.force-enabled" = true;
            "gfx.webrender.enabled" = true;
          };
          
          # Set up extensions
          extensions = with pkgs.nur.repos.rycee.firefox-addons; [
            ublock-origin
            darkreader
            bitwarden
            history-cleaner
            simple-tab-groups
            tab-session-manager
            privacy-badger
            clearurls
            h264ify            # Better YouTube performance
            sponsorblock      # Skip sponsored segments
            tridactyl         # Vim-like controls
            firefox-translations # Built-in translator
            improved-container-tabs # Better container tab management
          ];
          
          # Custom userChrome.css for a more compact UI
          userChrome = ''
            /* Hide tabs when there is only one tab */
            #tabbrowser-tabs .tabbrowser-tab:only-of-type { display: none !important; }
            
            /* More compact UI */
            :root {
              --tab-min-height: 28px !important;
              --tab-border-radius: 0 !important;
              --toolbarbutton-inner-padding: 5px !important;
              --arrowpanel-padding: 0.8em !important;
              --arrowpanel-menuitem-padding: 4px 8px !important;
            }
            
            /* Reduce tab spacing */
            .tab-content {
              padding: 0 5px !important;
            }
            
            /* Reduce URL bar height */
            #urlbar, .searchbar-textbox {
              font-size: 14px !important;
              min-height: 24px !important;
            }
            
            /* Reduce toolbar height */
            #nav-bar {
              padding: 2px !important;
            }
          '';
          
          # Custom user.js for additional settings
          extraConfig = ''
            // Disable Pocket
            user_pref("extensions.pocket.enabled", false);
            
            // Force GPU acceleration
            user_pref("layers.acceleration.force-enabled", true);
            
            // Disable default browser check
            user_pref("browser.shell.checkDefaultBrowser", false);
          '';
        };
        
        # Work profile with different container tabs
        work = {
          id = 1;
          name = "work";
          
          # Inherit most settings from default profile
          settings = config.programs.firefox.profiles.default.settings // {
            "privacy.userContext.enabled" = true; # Enable container tabs
            "privacy.userContext.ui.enabled" = true;
          };
          
          # Work-specific extensions
          extensions = with pkgs.nur.repos.rycee.firefox-addons; [
            ublock-origin
            darkreader
            bitwarden
            multi-account-containers # Container tabs for work
            firefox-translations
          ];
        };
      };
    };
    
    # Add NUR repo for Firefox extensions
    nixpkgs.config.packageOverrides = pkgs: {
      nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/master.tar.gz") {
        inherit pkgs;
      };
    };
  };
} 