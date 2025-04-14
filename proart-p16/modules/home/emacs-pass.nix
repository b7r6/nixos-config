# Emacs configuration for password-store (pass) integration
{ config, lib, pkgs, ... }:

{
  options.emacs.password-store = {
    enable = lib.mkEnableOption "Enable password-store integration for Emacs";
    
    gpgIdFile = lib.mkOption {
      type = lib.types.str;
      default = "~/.password-store/.gpg-id";
      description = "Path to .gpg-id file for password-store";
    };
    
    passwordLength = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Default length for generated passwords";
    };
  };

  config = lib.mkIf config.emacs.password-store.enable {
    # Make sure the password-store program is installed
    programs.password-store = {
      enable = true;
      package = pkgs.pass;
      settings = {
        PASSWORD_STORE_DIR = "$HOME/.password-store";
        PASSWORD_STORE_KEY = "$(cat ${config.emacs.password-store.gpgIdFile})";
        PASSWORD_STORE_CLIP_TIME = "45";
        PASSWORD_STORE_GENERATED_LENGTH = toString config.emacs.password-store.passwordLength;
      };
    };
    
    # Ensure GPG is properly configured
    programs.gpg = {
      enable = true;
      settings = {
        # Default key
        default-key = "$(cat ${config.emacs.password-store.gpgIdFile})";
        # Prioritize stronger algorithms
        personal-cipher-preferences = "AES256 AES192 AES";
        personal-digest-preferences = "SHA512 SHA384 SHA256";
        personal-compress-preferences = "ZLIB BZIP2 ZIP Uncompressed";
      };
    };
    
    # Install pinentry for GPG passphrase entry
    home.packages = with pkgs; [
      pinentry-emacs  # Pinentry for Emacs
    ];
    
    # Add Emacs packages for pass integration
    programs.emacs = {
      # Only modify Emacs config if Emacs is enabled
      extraPackages = lib.mkIf config.programs.emacs.enable (epkgs: with epkgs; [
        password-store     # Base pass.el for password-store integration
        auth-source-pass   # Integration with Emacs auth-source
        pass               # Enhanced UI for password-store
        password-store-otp # OTP support for password-store
      ]);
    };
    
    # Add Emacs configuration for password-store
    home.file.".emacs.d/personal-config/pass-config.el" = {
      text = ''
        ;; Password Store (pass) integration for Emacs
        
        ;; Auth-source configuration for pass
        (require 'auth-source-pass)
        (auth-source-pass-enable)
        
        ;; Make pass the default auth source
        (setq auth-sources '(password-store))
        
        ;; Password-store configuration
        (require 'password-store)
        (setq password-store-password-length ${toString config.emacs.password-store.passwordLength})
        
        ;; Key bindings for password-store
        (global-set-key (kbd "C-c p p") 'password-store-copy)
        (global-set-key (kbd "C-c p g") 'password-store-generate)
        (global-set-key (kbd "C-c p i") 'password-store-insert)
        (global-set-key (kbd "C-c p r") 'password-store-rename)
        (global-set-key (kbd "C-c p e") 'password-store-edit)
        (global-set-key (kbd "C-c p d") 'password-store-remove)
        (global-set-key (kbd "C-c p u") 'password-store-url)
        
        ;; Ivy/Counsel integration if available
        (when (featurep 'ivy)
          (global-set-key (kbd "C-c p f") 'counsel-password-store))
        
        ;; OTP support
        (when (featurep 'password-store-otp)
          (global-set-key (kbd "C-c p o") 'password-store-otp-token-copy))
        
        ;; Integration with org-mode for secure links
        (with-eval-after-load 'org
          (defun org-pass-store-link ()
            "Store a link to a password-store entry."
            (when (string-match "^\\*password-store\\*" (buffer-name))
              (let* ((entry (password-store--completing-read))
                     (link (format "pass:%s" entry))
                     (description (format "Password Store: %s" entry)))
                (org-store-link-props
                 :type "pass"
                 :link link
                 :description description))))
          
          (org-link-set-parameters
           "pass"
           :follow (lambda (path) (password-store-copy path))
           :store 'org-pass-store-link))
        
        ;; Automatically clear clipboard after use
        (setq password-store-time-before-clipboard-restore 45)
        
        ;; Custom function to generate and insert credentials
        (defun my/password-store-generate-and-insert (entry user)
          "Generate a password for ENTRY and insert it along with USER."
          (interactive "sPassword entry: \nsUsername: ")
          (let ((password (password-store--generate-password password-store-password-length)))
            (password-store-insert-text entry (format "Username: %s\nPassword: %s\n" user password))
            (message "Generated and inserted credentials for '%s'" entry)))
        
        (global-set-key (kbd "C-c p G") 'my/password-store-generate-and-insert)
        
        ;; Setup pinentry for Emacs
        (setq epg-pinentry-mode 'loopback)
        
        ;; Provide a hydra menu for password-store if hydra is available
        (when (featurep 'hydra)
          (defhydra hydra-pass (:color blue :hint nil)
        "
        ^Copy^              ^Create/Edit^           ^Other^
        ^^^^^^^^-----------------------------------------------------------------
        _p_: copy password  _g_: generate password  _f_: find entry
        _u_: copy username  _i_: insert entry       _r_: rename entry
        _U_: copy url       _e_: edit entry         _d_: delete entry
        _o_: copy OTP       _G_: generate & insert  _q_: quit
        "
            ("p" password-store-copy)
            ("u" (lambda () (interactive)
                   (password-store--completing-read)
                   (password-store--read-field "Username")))
            ("U" password-store-url)
            ("o" password-store-otp-token-copy)
            ("g" password-store-generate)
            ("i" password-store-insert)
            ("e" password-store-edit)
            ("G" my/password-store-generate-and-insert)
            ("f" counsel-password-store)
            ("r" password-store-rename)
            ("d" password-store-remove)
            ("q" nil "quit"))
          
          (global-set-key (kbd "C-c P") 'hydra-pass/body))
      '';
    };
  };
} 