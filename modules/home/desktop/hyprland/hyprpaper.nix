{ cfg, ... }:

let
  wallpaperPath = "$HOME/.config/hypr/wallpaper.jpg";
in
{
  enable = cfg.wallpaperMode == "hyprpaper";

  settings = {
    preload = [ wallpaperPath ];
    wallpaper = [ ",${wallpaperPath}" ];
    ipc = true;
    splash = false;
  };
}
