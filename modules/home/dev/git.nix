# TODO[b7r6]: reconciel this with the original stuff...
{ config, pkgs, ... }:
{
  programs.git = {
    enable = true;

    userName = config.me.username;
    userEmail = config.me.email;

    # TODO[b7r6]: https://blog.gitbutler.com/how-git-core-devs-configure-git/
    extraConfig = {
      init.defaultBranch = "main";

      pull.rebase = true;
      rebase.autoStash = true;

      fetch.prune = true;
      push.autoSetupRemote = true;

      core = { };

      diff = {
        colorMoved = "default";
      };

      credential.helper = "${pkgs.git-credential-manager}/bin/git-credential-manager";
    };

    # Common aliases for git commands
    aliases = {
      st = "status";
      ci = "commit";
      co = "checkout";
      br = "branch";

      unstage = "reset HEAD --";
      last = "log -1 HEAD";
      visual = "!gitk";

      # Better log visualization
      lg = "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit";

      # Find commits by commit message
      fm = "!f() { git log --pretty=format:'%C(yellow)%h  %Cblue%ad  %Creset%s%Cgreen  [%cn] %Cred%d' --decorate --date=short --grep=$1; }; f";

      # Show modified files in last commit
      dl = "!git ll -1";

      # Show a diff of the last commit
      dlc = "diff --cached HEAD^";
    };

    ignores = [
      ".DS_Store"
      "*.swp"
      ".direnv/"
      ".envrc"
      "result"
      "result-*"
    ];
  };

  # Install additional git-related tools
  home.packages = with pkgs; [
    git-credential-manager
    git-lfs
  ];
}
