# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // sddm
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Frame zero, done properly: SDDM (Qt6, wayland greeter) with the hypermodern
# theme — the SAME wallpaper shader as the desktop/lock/shell layers, Azonix
# clock, IDENTIFY posture, palette generated at build time from lib.nix (the
# math the parity gate pins). SDDM owns seats, VTs, and session lifecycle —
# the parts the hand-rolled greetd compositor chain got wrong (wedged seat,
# dead Ctrl+Alt+Fn, respawn hazards).
#
# The session entry keeps the start-hyprland wrapper: journal-routed
# compositor logs + the zombie-session teardown that makes killed compositors
# leave clean state.
{
  config,
  lib,
  pkgs,
  flake,
  ...
}:
let
  # The EYES card as frame zero's frame zero: one kernel-rendered still
  # behind the login prompt, same scene the live wallpaper runs after login.
  eyesStill = import ../../home/themes/wallpapers/eyes-still.nix { inherit pkgs flake; };

  # Session launcher (carried over from the greetd era). Jobs:
  #   - seed the session identity vars
  #   - route the compositor's stdout/stderr into the journal
  #   - TEAR DOWN systemd user session state after Hyprland exits, however
  #     it exits — no zombie targets, no stale WAYLAND_DISPLAY.
  start-hyprland = pkgs.writeShellScriptBin "start-hyprland" ''
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=Hyprland
    systemd-cat --identifier=hyprland Hyprland "$@"
    status=$?
    systemctl --user stop hyprland-session.target graphical-session.target 2>/dev/null || true
    systemctl --user unset-environment \
      WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE 2>/dev/null || true
    # sweep dead instance dirs — they accumulate on crashes and poison
    # signature discovery for everything that trusts newest-first
    rm -rf "''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr" 2>/dev/null || true
    exit $status
  '';

  hypermodernSession =
    (pkgs.writeTextFile {
      name = "hypermodern-session";
      destination = "/share/wayland-sessions/hypermodern.desktop";
      text = ''
        [Desktop Entry]
        Name=hypermodern
        Comment=Hyprland via start-hyprland (journal + session teardown)
        Exec=${start-hyprland}/bin/start-hyprland
        Type=Application
      '';
    })
    // {
      providedSessions = [ "hypermodern" ];
    };

  color-lib = import ../../flake/themes/lib.nix { inherit lib; };
  palette = color-lib.make-palette { level = "carbon"; };

  # theme.conf keys surface in the theme QML as the `config` context object.
  themeConf = pkgs.writeText "theme.conf" ''
    [General]
    type=color
    background=
    loginUser=${config.hyper-modern-nixos.greeter.user}
    hostName=${config.networking.hostName}
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: "${k}=${v}") (
        lib.getAttrs (map (n: "base0${n}") [
          "0"
          "1"
          "2"
          "3"
          "4"
          "9"
          "A"
        ]) palette
      )
    )}
  '';

  hypermodernSddmTheme =
    pkgs.runCommand "hypermodern-sddm-theme" { nativeBuildInputs = [ pkgs.qt6.qtshadertools ]; }
      ''
        dir=$out/share/sddm/themes/hypermodern
        mkdir -p $dir
        cp ${./Main.qml} $dir/Main.qml
        cp ${themeConf} $dir/theme.conf
        ${lib.optionalString config.hyper-modern-nixos.greeter.eyesStill "cp ${eyesStill}/eyes.png $dir/eyes.png"}
        cp ${../../home/new-suzuki/shell/modules/wallpaper/wallpaper.frag} $dir/wallpaper.frag
        qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
          -o $dir/wallpaper.frag.qsb $dir/wallpaper.frag

        cat > $dir/metadata.desktop <<EOF
        [SddmGreeterTheme]
        Name=hypermodern
        Description=ono-sendai frame zero — the wallpaper field at the login prompt
        Type=sddm-theme
        Version=1.0
        MainScript=Main.qml
        ConfigFile=theme.conf
        QtVersion=6
        EOF
      '';
in
{
  options.hyper-modern-nixos.greeter.user = lib.mkOption {
    type = lib.types.str;
    default = "b7r6";
    description = "Account the greeter pre-selects (single-operator fleet).";
  };

  # Opt-in: the kernel-rendered EYES still behind the login prompt pulls
  # straylight-nvidia-sdk (CUDA), so only GB10 hosts want it. Off → the
  # greeter's animated shader field shows alone (Main.qml's Image falls back
  # to the field when eyes.png is absent), and no host without the SDK is
  # forced to fetch it (the derivation is only referenced when this is true).
  options.hyper-modern-nixos.greeter.eyesStill = lib.mkEnableOption "kernel-rendered EYES still behind the greeter (needs the CUDA SDK; GB10 only)";

  config = {
    services.displayManager = {
      sddm = {
        enable = true;
        package = pkgs.kdePackages.sddm; # Qt6
        wayland.enable = true;
        theme = "hypermodern";
        extraPackages = [ pkgs.kdePackages.qtsvg ];
      };
      sessionPackages = [ hypermodernSession ];
      defaultSession = "hypermodern";
    };

    environment.systemPackages = [
      hypermodernSddmTheme
      start-hyprland # bare-TTY escape hatch keeps working
    ];

    # The greeter renders the display faces from the SYSTEM font set.
    fonts.packages = [
      (pkgs.callPackage ../../home/new-suzuki/azonix.nix { })
      (pkgs.callPackage ../../home/themes/fonts/berkeley-mono { })
    ];
  };
}
