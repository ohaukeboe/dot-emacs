{ secrets, ... }:

let
  mainKey = ".ssh/pubkeys/main.pub";
  oldKey = ".ssh/pubkeys/old.pub";
  trashcanKey = ".ssh/pubkeys/trashcan.pub";
  piKey = ".ssh/pubkeys/pi.pub";
in
{
  programs.ssh = {
    enable = true;

    serverAliveInterval = 30;
    serverAliveCountMax = 3;
    controlMaster = "auto";
    controlPath = "/tmp/ssh-%u-%r@%h:%p";
    controlPersist = "10m";

    extraOptionOverrides = {
      # TODO: make this dynamic based on the environment
      identityAgent = "~/.1password/agent.sock";
    };

    matchBlocks = {
      "desktop" = {
        hostname = secrets.ssh_host.desktop;
        user = "oskar";
        identityFile = "~/${mainKey}";
      };

      "killono" = {
        hostname = secrets.ssh_host.killono;
        user = "oskar";
        identityFile = "~/${oldKey}";
      };

      "uio" = {
        hostname = "login.uio.no";
        user = "oskah";
        identityFile = "~/${mainKey}";
        forwardX11 = true;
        forwardX11Trusted = true;
      };

      "ifi" = {
        hostname = "login.ifi.uio.no";
        user = "oskah";
        identityFile = "~/${mainKey}";
        proxyJump = "uio";
        forwardX11 = true;
        forwardX11Trusted = true;
      };

      "bayer" = {
        hostname = secrets.ssh_host.bayer;
        user = "drift";
        identityFile = "~/${trashcanKey}";
      };

      "joe" = {
        hostname = secrets.ssh_host.joe;
        user = "drift";
        identityFile = "~/${trashcanKey}";
      };

      "github.com" = {
        hostname = "github.com";
        identityFile = "~/${mainKey}";
      };

      "github.uio.no" = {
        hostname = "github.uio.no";
        identityFile = "~/${oldKey}";
      };

      "pi" = {
        hostname = secrets.ssh_host.pi;
        user = "oskar";
        identityFile = "~/${piKey}";
      };

      "vm" = {
        hostname = "192.168.122.16";
        user = "oskar";
        identityFile = "~/${mainKey}";
      };

      "mininet" = {
        hostname = "localhost";
        user = "mininet";
        port = 8022;
        identityFile = "~/${mainKey}";
      };

      "laptop" = {
        hostname = secrets.ssh_host.laptop;
        user = "oskar";
        identityFile = "~/${mainKey}";
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
    "${trashcanKey}".text = "TODO";
    "${piKey}".text =
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJuhePKrlYe5FtKa8SA2thRyezpLu8WrNJq1AqsNsN/P";
  };
}
