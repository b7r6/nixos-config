{ config, lib, ... }: {
  options = {
    me = {
      username = lib.mkOption {
        type = lib.types.str;
        description = "Your username as shown by `id -un`";
      };

      fullname = lib.mkOption {
        type = lib.types.str;
        description = "Your full name for use in Git config";
      };

      email = lib.mkOption {
        type = lib.types.str;
        description = "Your email for use in Git config";
      };
    };
  };

  config = {
    home.username = config.me.username;

    assertions = [
      {
        assertion = config.me.username != null;
        message = "Username must be set via the me.username option";
      }
      {
        assertion = config.me.fullname != null;
        message = "Full name must be set via the me.fullname option";
      }
      {
        assertion = config.me.email != null;
        message = "Email must be set via the me.email option";
      }
    ];
  };
}
