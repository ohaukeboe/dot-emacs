{
  config,
  lib,
  pkgs,
  ...
}:

{
  nixpkgs.config.allowUnfreePredicate = import ../common/unfree-predicates.nix { inherit lib; };
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.settings.auto-optimise-store = true;

  boot.kernelPackages = pkgs.linuxPackages_zen;

  # Use the systemd-boot EFI boot loader.
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };

    efi.canTouchEfiVariables = true;
  };

  hardware.keyboard.zsa.enable = true;
  hardware.logitech.wireless.enable = true;

  # For the gc to work, it is important that the boot-loader stops
  # referencing old configurations (`configurationLimit' needs to be set)
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
    randomizedDelaySec = "45min";
  };

  # networking.hostName = "x1_laptop"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Europe/Oslo";
  i18n.extraLocales = [ "nb_NO.UTF-8/UTF-8" ];

  # Enable the X11 windowing system.
  # services.xserver.enable = true;

  services.displayManager.cosmic-greeter.enable = true;
  services.desktopManager.cosmic.enable = true;
  services.system76-scheduler.enable = true;
  services.gnome.gnome-keyring.enable = true;

  environment.sessionVariables = {
    QT_QPA_PLATFORMTHEME = "gtk3";
  };

  systemd.services.fprintd = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "simple";
  };
  services.fprintd.enable = true;

  programs.kdeconnect.enable = true;

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  services.tailscale.enable = true;

  services.resolved = {
    enable = true;
    dnsovertls = "opportunistic";
    fallbackDns = [ "1.1.1.1" ];
  };

  # Improve compatibility with programs/scripts not made for nix
  services.envfs.enable = true;
  programs.nix-ld.enable = true;

  services.flatpak.enable = true;
  xdg.portal.wlr.enable = true;
  xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-cosmic ];
  xdg.portal.config.common.default = "cosmic";
  xdg.portal.enable = true;

  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = [ "oskar" ];
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      vhostUserPackages = with pkgs; [ virtiofsd ];
      swtpm.enable = true;
    };
  };
  virtualisation.spiceUSBRedirection.enable = true;

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "riscv64-linux"
  ];

  virtualisation.docker = {
    enable = true;
    storageDriver = "btrfs";
    autoPrune.enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
      daemon.settings = {
        dns = [
          "1.1.1.1"
          "8.8.8.8"
        ];
        registry-mirrors = [ "https://mirror.gcr.io" ];
      };
    };
  };

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true; # Required for containers under podman-compose to be able to talk to each other.
      autoPrune.enable = true;
    };
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.oskar = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      "podman"
      "wireshark"
    ];
  };

  # programs.firefox.enable = true;
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "oskar" ]; # TODO: don't hard-code username
  };

  programs.wireshark = {
    enable = true;
    usbmon.enable = true;
  };

  environment.etc = {
    "1password/custom_allowed_browsers" = {
      text = ''
        .zen-wrapped
        zen
      '';
      mode = "0755";
    };
  };

  programs.fish.enable = true;
  users.defaultUserShell = pkgs.fish;

  programs.partition-manager.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    tree
    lsof
    zip
    unzip
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;
}
