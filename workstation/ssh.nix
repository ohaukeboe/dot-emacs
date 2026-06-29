{ secrets, pkgs, ... }:

let
  mainKey = ".ssh/pubkeys/main.pub";
  oldKey = ".ssh/pubkeys/old.pub";
  trashcanKey = ".ssh/pubkeys/trashcan.pub";
  piKey = ".ssh/pubkeys/pi.pub";
in
{
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
        # TODO: make this dynamic based on the environment
        IdentityAgent = "~/.1password/agent.sock";
        IdentitiesOnly = true;
      };
      "desktop" = {
        HostName = secrets.ssh_host.desktop;
        User = "oskar";
        IdentityFile = "~/${mainKey}";
        ForwardAgent = true;
      };

      "work-laptop" = {
        HostName = secrets.ssh_host.work-laptop;
        User = "oskar";
        IdentityFile = "~/${mainKey}";
        ForwardAgent = true;
      };

      "killono" = {
        HostName = secrets.ssh_host.killono;
        User = "oskar";
        IdentityFile = "~/${oldKey}";
      };

      "deepthought" = {
        HostName = secrets.ssh_host.deepthought;
        User = "deepthought";
        IdentityFile = "~/${mainKey}";
      };

      "deploy-deepthought" = {
        HostName = secrets.ssh_host.deepthought;
        User = "root";
        IdentityFile = "~/${mainKey}";
      };

      "uio" = {
        HostName = "login.uio.no";
        User = "oskah";
        IdentityFile = "~/${mainKey}";
        ForwardX11 = true;
        ForwardX11Trusted = true;
      };

      "ifi" = {
        HostName = "login.ifi.uio.no";
        User = "oskah";
        IdentityFile = "~/${mainKey}";
        ProxyJump = "uio";
        ForwardX11 = true;
        ForwardX11Trusted = true;
      };

      "bayer" = {
        HostName = secrets.ssh_host.bayer;
        User = "drift";
        IdentityFile = "~/${trashcanKey}";
      };

      "joe" = {
        HostName = secrets.ssh_host.joe;
        User = "drift";
        IdentityFile = "~/${trashcanKey}";
      };

      "github.com" = {
        HostName = "github.com";
        IdentityFile = "~/${mainKey}";
      };

      "github.uio.no" = {
        HostName = "github.uio.no";
        IdentityFile = "~/${oldKey}";
      };

      "pi" = {
        HostName = secrets.ssh_host.pi;
        User = "oskar";
        IdentityFile = "~/${piKey}";
      };

      "laptop" = {
        HostName = secrets.ssh_host.laptop;
        User = "oskar";
        IdentityFile = "~/${mainKey}";
        ForwardAgent = true;
      };
    };
  };

  home.file = {
    # These are the public keys used to identify what key to use. The
    # private keys are stored in 1Password
    "${mainKey}".text =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILToVl9RmOhn1TaQHiDPIS1/TGbHeA6ssTTocJmv5Yvf";
    "${oldKey}".text =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKf4tcGBaTRbaBzgy7QbGcbL5E0ShA2EC0C5OwhZukkl";
    "${trashcanKey}".text =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBWtqnZik41LZmBiVQK/d46GpuZT23uhpplZmcHBFOSC";
    "${piKey}".text =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJuhePKrlYe5FtKa8SA2thRyezpLu8WrNJq1AqsNsN/P";

    ".config/1Password/ssh/agent.toml".source = (pkgs.formats.toml { }).generate "1password-agent" {
      ssh-keys = [
        { vault = "Private"; }
        { vault = "Employee"; }
        { vault = "320-Drift"; }
      ];
    };
  };
}
