{
  config,
  lib,
  pkgs,
  private,
  ...
}:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  # Decrypted by sops-nix at runtime; never present in the Nix store.
  mainKey = config.sops.secrets."ssh/main".path;
  oldKey = config.sops.secrets."ssh/old".path;
  trashcanKey = config.sops.secrets."ssh/trashcan".path;
in
{
  # A plain ssh-agent with no GUI, desktop-session or biometric dependency, so
  # it works over a bare TTY or an incoming SSH login. Home Manager only sets
  # SSH_AUTH_SOCK when SSH_CONNECTION is unset, so a forwarded agent still wins.
  services.ssh-agent.enable = true;

  # sops-nix decrypts in a systemd user oneshot, so ssh-add must be ordered
  # after it. Needs a lingering user for the keys to be loaded before the first
  # interactive login on a freshly booted machine; on NixOS that comes from
  # `users.users.<name>.linger`, elsewhere from `loginctl enable-linger`.
  systemd.user.services.ssh-add-keys = lib.mkIf isLinux {
    Unit = {
      Description = "Load SSH keys into the agent";
      After = [
        "sops-nix.service"
        "ssh-agent.service"
      ];
      Wants = [
        "sops-nix.service"
        "ssh-agent.service"
      ];
    };
    Service = {
      Type = "oneshot";
      Environment = [ "SSH_AUTH_SOCK=%t/${config.services.ssh-agent.socket}" ];
      ExecStart = "${lib.getExe' pkgs.openssh "ssh-add"} ${mainKey} ${oldKey} ${trashcanKey}";
    };
    Install.WantedBy = [ "default.target" ];
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings = {
      "*" = {
        ServerAliveInterval = 30;
        ServerAliveCountMax = 3;
        ControlMaster = "auto";
        ControlPath = "/tmp/ssh-%u-%r@%h:%p";
        ControlPersist = "10m";
        IdentitiesOnly = true;
        # No IdentityAgent: it would override SSH_AUTH_SOCK on every machine
        # this config is deployed to, discarding forwarded agents on arrival.
        AddKeysToAgent = "yes";
      };
      "desktop" = {
        HostName = private.ssh_host.desktop;
        User = "oskar";
        IdentityFile = mainKey;
      };

      "laptop" = {
        HostName = private.ssh_host.laptop;
        User = "oskar";
        IdentityFile = mainKey;
      };

      "work-laptop" = {
        HostName = private.ssh_host.work-laptop;
        User = "oskar";
        IdentityFile = mainKey;
      };

      "killono" = {
        HostName = private.ssh_host.killono;
        User = "oskar";
        IdentityFile = oldKey;
      };

      "deepthought" = {
        HostName = private.ssh_host.deepthought;
        User = "deepthought";
        IdentityFile = mainKey;
      };

      "deploy-deepthought" = {
        HostName = private.ssh_host.deepthought;
        User = "root";
        IdentityFile = mainKey;
      };

      "bayer" = {
        HostName = private.ssh_host.bayer;
        User = "drift";
        IdentityFile = trashcanKey;
      };

      "joe" = {
        HostName = private.ssh_host.joe;
        User = "drift";
        IdentityFile = trashcanKey;
      };

      "github.com" = {
        HostName = "github.com";
        IdentityFile = mainKey;
      };
    };
  };
}
