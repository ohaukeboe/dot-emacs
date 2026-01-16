{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.modules.sshd;
in
{
  options.modules.sshd = {
    enable = mkEnableOption "SSH daemon with secure defaults";

    authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILToVl9RmOhn1TaQHiDPIS1/TGbHeA6ssTTocJmv5Yvf"
      ];
      description = "List of SSH public keys authorized for the oskar user";
    };
  };

  config = mkIf cfg.enable {
    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    users.users.oskar.openssh.authorizedKeys.keys = cfg.authorizedKeys;
  };
}
