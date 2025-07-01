_: {
  programs = {
    bash = {
      enable = true;
      initExtra = ''
        # Custom bash profile goes here
      '';

      historyControl = [
        "ignoredups"
        "erasedups"
      ];

      historyFileSize = 10000;
      historySize = 10000;

      sessionVariables = {
        TERM = "xterm-256color";
        COLORTERM = "TRUECOLOR";
        COLORFGBG = "15;0";
      };
    };

    zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      envExtra = ''
        # Custom ~/.zshenv goes here
      '';
      profileExtra = ''
        # Custom ~/.zprofile goes here
      '';
      loginExtra = ''
        # Custom ~/.zlogin goes here
      '';
      logoutExtra = ''
        # Custom ~/.zlogout goes here
      '';
    };
  };
}
