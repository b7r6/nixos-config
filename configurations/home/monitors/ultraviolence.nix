{ ... }: {
  # DP-5 (left) | DP-3 (center) | DP-4 (right)
  hyper-modern-nixos.hyprland.monitors = {
    left = {
      description = "ASUSTek COMPUTER INC PG32UCDP SCLMQS022729";
      resolution = "3840x2160";
      refreshRate = 120;
      position = "0x0";
      scale = 1.5;
      workspaces = [
        1
        2
        3
        4
        5
      ];
    };

    center = {
      description = "ASUSTek COMPUTER INC PG32UCDP T1LMQS044820";
      resolution = "3840x2160";
      refreshRate = 120;
      position = "2560x0";
      scale = 1.5;
      workspaces = [
        6
        7
        8
        9
        10
      ];
      primary = true;
    };

    right = {
      description = "LG Electronics LG ULTRAGEAR+ 502NTMX7E483";
      resolution = "3840x2160";
      refreshRate = 144;
      position = "5120x0";
      scale = 1.5;
      workspaces = [
        11
        12
        13
        14
        15
      ];
    };
  };
}
