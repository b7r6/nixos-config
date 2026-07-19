# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                            // hyper-modern-nixos // greetd
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Frame zero wears the SECURED posture: greetd runs the hypermodern quickshell
# greeter under cage (the canonical graphical-greeter kiosk) — the same
# wallpaper shader as the desktop/lock at forced full-facility register, the
# Azonix clock, and a password field driving greetd's IPC directly.
#
# The greeter runs as its own user with no access to any session state, so
# the palette is generated at BUILD time from lib.nix (the same math the
# parity gate pins) at the fleet-default vector: carbon, 211/201.
#
# Escape hatches: getty stays on tty2+ (NixOS default), so a broken greeter
# never locks the machine; `nixos-rebuild --rollback` over SSH does the rest.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Session launcher. Two jobs beyond bare `Hyprland`:
  #   - seed the session identity vars greeters don't set
  #   - route the compositor's stdout/stderr into the journal — otherwise
  #     Hyprland's log output from a greetd session goes nowhere
  start-hyprland = pkgs.writeShellScriptBin "start-hyprland" ''
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=Hyprland
    exec systemd-cat --identifier=hyprland Hyprland "$@"
  '';

  color-lib = import ../flake/themes/lib.nix { inherit lib; };
  palette = color-lib.make-palette { level = "carbon"; };

  greeterConfig = pkgs.writeText "greeter-config.json" (
    builtins.toJSON {
      user = config.hyper-modern-nixos.greeter.user;
      session = "${start-hyprland}/bin/start-hyprland";
      host = config.networking.hostName;
      palette = lib.getAttrs (map (n: "base0${n}") [
        "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "A" "B" "C" "D" "E" "F"
      ]) palette;
    }
  );

  # The greeter shell: QML + the SAME wallpaper shader the desktop/lock use,
  # compiled to Qt bytecode at build time.
  greeterShell =
    pkgs.runCommand "hypermodern-greeter"
      {
        nativeBuildInputs = [ pkgs.qt6.qtshadertools ];
      }
      ''
        mkdir -p $out
        cp ${./greeter/shell.qml} $out/shell.qml
        cp ${../home/new-suzuki/shell/modules/wallpaper/wallpaper.frag} $out/wallpaper.frag
        qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 \
          -o $out/wallpaper.frag.qsb $out/wallpaper.frag
        cp ${greeterConfig} $out/config.json
      '';

  greeter-cmd = pkgs.writeShellScriptBin "hypermodern-greeter" ''
    export QT_QPA_PLATFORM=wayland
    exec ${pkgs.cage}/bin/cage -s -- ${pkgs.quickshell}/bin/quickshell -p ${greeterShell}
  '';
in
{
  options.hyper-modern-nixos.greeter.user = lib.mkOption {
    type = lib.types.str;
    default = "b7r6";
    description = "Account the greeter authenticates (single-operator fleet).";
  };

  config = {
    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${greeter-cmd}/bin/hypermodern-greeter";
          user = "greeter";
        };
      };
    };

    # The greeter session needs the display faces at the SYSTEM level (it is
    # not the user's home): Azonix for the clock, Berkeley Mono for the rest.
    fonts.packages = [
      (pkgs.callPackage ../home/new-suzuki/azonix.nix { })
      (pkgs.callPackage ../home/themes/fonts/berkeley-mono { })
    ];

    # also on PATH so a bare TTY login can start the same session by hand
    environment.systemPackages = [ start-hyprland ];

    # greetd holds a logind session for the greeter user (uid 989). that session
    # needs a functioning user@989.service (with dbus socket) or switch-to-
    # configuration-ng fails when it tries to reload user units for the greeter.
    #
    # ordering:
    # - wait for multi-user.target (no scribble on the login prompt)
    # - want user@989.service (keep the greeter's user manager alive)
    systemd.services.greetd = {
      after = [
        "multi-user.target"
        "user@989.service"
      ];
      wants = [ "user@989.service" ];
    };
  };
}
