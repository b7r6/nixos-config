_: {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks = {
      # Default settings for all hosts
      "*" = {
        forwardAgent = true;
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
