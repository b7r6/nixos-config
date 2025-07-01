_: {
  programs.ssh = {
    enable = true;
    forwardAgent = true;

    matchBlocks = {
      # Default settings for all hosts
      "*" = {
        extraOptions = {
          AddKeysToAgent = "yes";
          StrictHostKeyChecking = "accept-new";
        };
      };

      "github.com" = {
        user = "git";
      };
    };
  };
}
