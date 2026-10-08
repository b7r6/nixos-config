# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // hyper-modern-nixos // base
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Core system settings: SSH, sudo, home-manager integration.
#
{ config, lib, pkgs, ... }:
let
  # On impermanence hosts the root is wiped on boot, so host keys must live under
  # the persist volume to survive. On normal hosts they belong at the standard
  # /etc/ssh location. This is NOT cosmetic: agenix derives age.identityPaths from
  # services.openssh.hostKeys, so pointing this at /persist on a non-impermanence
  # host makes sshd generate a brand-new keypair there and agenix then tries to
  # decrypt with a key that isn't a registered recipient (secrets are keyed to the
  # original /etc/ssh host key in secrets/keys.nix) → "no identity matched any of
  # the recipients" at activation.
  imperm = config.hyper-modern-nixos.impermanence;
  sshKeyPrefix = if imperm.enable then "${imperm.persistPath}/etc/ssh" else "/etc/ssh";
in
{
  # SSH daemon — accept passwords, keys, whatever works. Security comes from
  # the network layer (tailscale, firewalls), not from crippling auth methods.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
    hostKeys = [
      {
        path = "${sshKeyPrefix}/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "${sshKeyPrefix}/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  # Use standard ssh-agent (conflicts with gnome-keyring's gcr-ssh-agent)
  # Set low priority so wayland module can override if gnome-keyring is enabled
  programs.ssh.startAgent = lib.mkDefault true;

  # Passwordless sudo for wheel group
  security.sudo.wheelNeedsPassword = false;

  # ── Password-quality policy (Secureframe "password policy" control) ─────────
  # The fleet is SSH-key-only (no password hashes), so this is rarely exercised,
  # but Secureframe/osquery reads the STATIC config — /etc/security/pwquality.conf
  # and the PAM password stack — so the control needs it present AND enforced.
  environment.etc."security/pwquality.conf".text = ''
    minlen = 12
    dcredit = -1
    ucredit = -1
    ocredit = -1
    lcredit = -1
    minclass = 3
    retry = 3
    enforce_for_root
  '';
  security.pam.services.passwd.rules.password.pwquality = {
    control = "required";
    modulePath = "${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so";
    # Run before pam_unix writes the hash, so a weak password is rejected.
    order = config.security.pam.services.passwd.rules.password.unix.order - 10;
    settings.conf = "/etc/security/pwquality.conf";
  };

  # Home-manager integration
  home-manager.useUserPackages = true;
  home-manager.useGlobalPkgs = true;
  home-manager.backupFileExtension = "hm-backup";

  # Required for xdg portals when using home-manager.useUserPackages
  environment.pathsToLink = [
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  # Handy nix helper
  programs.nh.enable = true;
}
