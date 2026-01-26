{ flake, pkgs, ... }:
let
  inherit (flake) inputs;
in
{
  imports = [
    ./bluetooth.nix
    ./cachix.nix
    ./docker.nix
    ./libvirt.nix
    ./myusers.nix
    ./network.nix
    ./network-manager.nix
    ./nvidia.nix
    ./nix-ld.nix
    ./radeon.nix
    ./secrets.nix
    ./usb.nix
  ];

  #
  # !! TODO[b7r6]: fix this uncategorized junk !!
  #

  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.permittedInsecurePackages = [
    "qtwebengine-5.15.19"
  ];
  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "hm-backup";

  services.openssh.enable = true;

  programs.ssh.startAgent = true;
  programs.nh.enable = true;

  hypermodern.network = {
    enable = true;
    tailnet.domain = "risk-nunki.ts.net";
    firewall.enable = false;
    useBackupResolver = true;
  };

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd Hyprland";
        user = "greeter";
      };
    };
  };

  nix = {
    package = pkgs.nixVersions.stable;

    extraOptions = ''
      experimental-features = nix-command flakes pipe-operators
    '';

    settings = {
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "@wheel"
      ];
    };

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  services.redis.enable = true;
  services.postgresql.enable = true;

  security.sudo.wheelNeedsPassword = false;

  programs.firefox.enable = true;
  environment.systemPackages = with pkgs; [
    # Base utilities
    atuin
    bat
    btop
    cacert
    curl
    fd
    fzf
    gh
    git
    git-lfs
    gitui
    home-manager
    jq
    lf
    neovim
    ripgrep
    tmux
    tree
    unzip
    vim
    wget
    xz
    zoxide

    dbus
    dconf

    wireshark
    wireshark-cli

    pciutils

    python312
    python313
    python314

    nvtopPackages.full

    # System diagnostics & performance
    # bcc # BPF Compiler Collection for Linux kernel tracing
    # bpftrace # High-level tracing language for Linux eBPF
    # ethtool # Network interface diagnostic tool
    # glances # System monitoring tool
    # htop # Interactive process viewer
    # iftop # Network bandwidth monitor
    # iotop # I/O monitoring tool
    # lm_sensors # Hardware monitoring tools
    # lsof # List open files
    # netdata # Real-time performance monitoring
    # nmon # Performance monitoring tool
    # # perf # Linux performance counters
    # pciutils # PCI utilities (lspci, etc)
    # powertop # Power consumption/management diagnosis
    # psmisc # Utilities for managing processes (pstree, killall, etc)
    # smartmontools # Hard drive diagnostic tools
    # stress-ng # Stress test utility
    # sysstat # System performance tools (iostat, mpstat, etc)
    # usbutils # USB utilities

    # # Network tools
    # bandwhich # Terminal bandwidth utilization tool
    # dnstracer # DNS debugging tool
    # dogdns # Command-line DNS client
    # gping # Ping with a graph
    # hping # Network probing tool
    # inetutils # Common network programs
    # ipcalc # IP address calculator
    # iperf3 # Network performance tool
    # iproute2 # Advanced networking tools
    # iw # Wireless configuration tool
    # mtr # Network diagnostic tool
    # # ncat # Networking utility from Nmap
    # ngrep # Network grep
    # nmap # Security scanner
    # # nping # Network packet generation tool
    # # openvpn # VPN client
    # socat # Multipurpose relay
    # speedtest-cli # Internet speed test
    # tcpdump # Network traffic analyzer
    # traceroute # Network path tracing
    # wireshark-cli # Network protocol analyzer (CLI)
    # whois # WHOIS lookup tool

    # # Security & pentesting
    # aircrack-ng # Wireless security assessment
    # amass # Network mapping of attack surfaces
    # binwalk # Firmware analysis tool
    # burpsuite # Web application security testing
    # chkrootkit # Rootkit detector
    # dirb # Web content scanner
    # exploitdb # Archive of exploits
    # ffuf # Web fuzzer
    # hashcat # Password recovery
    # hydra # Password cracking
    # john # Password cracking
    # masscan # Fast port scanner
    # metasploit # Penetration testing framework
    # nuclei # Vulnerability scanner
    # proxychains # Proxy chaining
    # # pwndbg # GDB debugging extension
    # radare2 # Reverse engineering framework
    # # rkhunter # Rootkit detection
    # rustscan # Fast port scanner
    # sqlmap # SQL injection scanner
    # sslscan # SSL/TLS scanner

    # # Forensics
    # autopsy # Digital forensics platform
    # ddrescue # Data recovery tool
    # foremost # File recovery
    # scalpel # File carver
    # sleuthkit # Filesystem analysis
    # testdisk # Data recovery

    # # Miscellaneous tools
    # file # File type identification
    # hexedit # Hex editor
    # magic-wormhole # Secure file transfer
    # netcat # TCP/IP swiss army knife
    # pv # Pipe viewer/progress meter
    # shellcheck # Shell script analysis
    # tcpreplay # Packet replay utility
    # termshark # Terminal UI for Wireshark
    # tshark # Terminal version of Wireshark
    # valgrind # Memory debugging and profiling
    # wrk # HTTP benchmarking tool
  ];

  services.udev.packages = [
    (pkgs.writeTextFile {
      name = "android-udev-rules";
      destination = "/etc/udev/rules.d/51-android.rules";
      text = ''
        # Google devices (Pixel, Nexus, etc.)
        SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666", GROUP="adbusers"
      '';
    })
  ];

  users.groups.adbusers = { };
  users.groups.wireshark = { };
  # programs.adb.enable removed in nixpkgs - systemd 258 handles uaccess rules automatically
  users.users.b7r6.extraGroups = [ "wireshark" ];
  # If using android-nixpkgs, you can include this part
  # This assumes you have android-nixpkgs set up in your imports
  # android-nixpkgs.androidenv = {
  #   includeSystemPackages = true;
  # };
}
