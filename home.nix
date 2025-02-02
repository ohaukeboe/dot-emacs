{ lib, pkgs, system, zen-browser, ... }:

{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "oskar";
  home.homeDirectory = "/home/oskar";

  manual.manpages.enable = false;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.05"; # Please read the comment before changing.

  programs.emacs = {
  	enable = true;
  	# package = pkgs.emacs-pgtk;
  	package = (pkgs.emacsWithPackagesFromUsePackage {
  	  package = pkgs.emacs-unstable-pgtk;
  	  config = ./config.org;
  	  alwaysEnsure = false;
  	  alwaysTangle = true;
  	  extraEmacsPackages = epkgs: with epkgs; [
  	    copilot
  	    jinx
        cdlatex
        auctex
        (lsp-mode.overrideAttrs (p: {
          buildPhase = ''
              export LSP_USE_PLISTS=true;
            '' + p.buildPhase;
        }))
        (lsp-ui.overrideAttrs (p: {
          buildPhase = ''
              export LSP_USE_PLISTS=true;
            '' + p.buildPhase;
        }))
        (dap-mode.overrideAttrs (p: {
          buildPhase = ''
              export LSP_USE_PLISTS=true;
            '' + p.buildPhase;
        }))
        (consult-lsp.overrideAttrs (p: {
          buildPhase = ''
              export LSP_USE_PLISTS=true;
            '' + p.buildPhase;
        }))
        (lsp-treemacs.overrideAttrs (p: {
          buildPhase = ''
              export LSP_USE_PLISTS=true;
            '' + p.buildPhase;
        }))
        (lsp-ltex.overrideAttrs (p: {
          buildPhase = ''
              export LSP_USE_PLISTS=true;
            '' + p.buildPhase;
        }))
        (lsp-java.overrideAttrs (p: {
          buildPhase = ''
              export LSP_USE_PLISTS=true;
            '' + p.buildPhase;
        }))
        (lsp-docker.overrideAttrs (p: {
          buildPhase = ''
              export LSP_USE_PLISTS=true;
            '' + p.buildPhase;
        }))
  	  ];
    });
  };


  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    # "keymapp"
    "terraform"
    "copilot-node-server"
  ];

  home.packages = with pkgs; [
    postgresql_16

    tailscale
    wakatime
    pympress # pdf presenter
    nexusmods-app

    ### fish ###
    babelfish

    ### zsa keyboard ###
    zsa-udev-rules
    # keymapp

    ### misc ###
    zotero_7
    firefox
    zen-browser.packages."${system}".default # for 1password to work, add '.zen-wrapped' to '/etc/1password/custom_allowed_browsers'
    sshfs
    devbox
    phoronix-test-suite
    ltex-ls # languagetool lsp
    packwiz
    languagetool
    zoxide
    gnuplot
    ditaa
    vlc
    pkg-config
    neofetch
    gh                          # github cli
    awscli2
    aws-nuke
    tealdeer # tldr
    protonmail-bridge
    davmail # bridge allowing to use exchange through IMAP

    git
    ripgrep
    fd

    ### terraform ###
    terraform
    terraform-ls

    ### reMarkable ###
    rmapi

    ### android ###
    android-tools


    ### Kotlin ###
    kotlin
    kotlin-language-server

    ### Assembly ###
    asm-lsp

    ### fonts ###
    roboto-mono
    roboto
    roboto-serif

    ### C ###
    man-pages
    man-pages-posix
    valgrind
    gdb
    gnumake

    clang-tools
    clang
    clang-analyzer
    (hiPrio gcc) # Needed hiPrio to resolve conflict as both
    # clang and gcc provide C++ binary
    ccls
    bear # usefull for using lsp

    ### C# ###
    omnisharp-roslyn

    ### .net ###
    dotnet-sdk_8
    mono

    ### rust ###
    rustup

    ### maude ###
    maude

    ### plantuml ###
    plantuml
    graphviz

    ### python ###
    #python312
    #mypy
    ## nodePackages_latest.pyright
    #python312Packages.numpy
    #python312Packages.packaging
    #python312Packages.matplotlib
    # python312Packages.jedi-language-server

    ### Java ###
    jdk
    # jdt-language-server
    # java-language-server
    maven
    gradle

    ### nix ###
    nil # lsp

    ### latex org ###
    texlive.combined.scheme-full
    python312Packages.pygments

    # org-inline-pdf
    pdf2svg
    imagemagick
    # org-download
    wl-clipboard
    # pandoc
    pandoc
    marksman
    # sqlite3
    sqlite

    enchant
    hunspellDicts.en_US
    hunspellDicts.nb_NO

    ### node ###
    nodePackages_latest.vscode-langservers-extracted
    nodejs
    nodePackages.typescript-language-server
    eslint

    ## chatgpt-shell
    pass

    ## mu4e (email)
    mu
    msmtp
    isync

    ### nixGL ###
    nixgl.nixVulkanIntel
    # nixgl.auto.nixVulkanNvidia


    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
  ] ++ builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts); # all nerd-fonts

  programs = {
    starship.enable = true;
    fish = {
      enable = true;
      interactiveShellInit = ''
      set fish_greeting # Disable greeting
    '';
      shellInit=''
      if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish' ]
        . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
      end

      fish_add_path ~/.dotnet/tools/
      fish_add_path ~/.local/bin/
      fish_add_path ~/.cargo/bin/

      alias git-del-merged='git branch --merged origin | grep -v -E " main\$| master\$" | xargs -pr git branch -d'

      alias edit='emacsclient -r -n'

      if test "$INSIDE_EMACS" = 'vterm'; and test -n "$EMACS_VTERM_PATH"; and test -f "$EMACS_VTERM_PATH/etc/emacs-vterm.fish"
        source "$EMACS_VTERM_PATH/etc/emacs-vterm.fish"
      end
    '';
    };

    direnv = {
      enable = true;
      # enableFishIntegration = true;
      nix-direnv.enable = true;
    };

    git = {
      enable = true;
      userName = "Oskar Haukebøe";
      userEmail = "ohaukeboe@pm.me";
      extraConfig = {
        log.decorate = "full";
      };
    };

    chromium = {
      enable = true;
      extensions = [
        "cjpalhdlnbpafiamejdnhcphjbkeiagm" # ublock origin
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa" # 1password
      ];
    };
  };

  systemd.user.services = {
    protonmail-bridge = {
      Unit = {
        Description = "ProtonMail Bridge";
        After = [ "network.target" ];
      };

      Service = {
        ExecStart = "${pkgs.protonmail-bridge}/bin/protonmail-bridge --noninteractive";
        Restart = "on-failure";
        Environment = "PATH=${pkgs.pass}/bin:${pkgs.gnupg}/bin:$PATH";
      };

      Install = {
        WantedBy = [ "default.target" ];
      };

    };

    davmail = {
      Unit = {
        Description = "DavMail Exchange Gateway";
        After = [ "network.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.davmail}/bin/davmail";
        Restart = "on-failure";
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };

  };

  # Allow home-manager to install fonts
  fonts.fontconfig.enable = true;

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".mbsyncrc".source = ./dotfiles/mbsyncrc.conf;
  };

  # Only create initial config if it doesn't exist
  home.activation = {
    createDavmailConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if [ ! -f ~/.davmail.properties ]; then
        cat > ~/.davmail.properties << EOF
davmail.url=https://outlook.office365.com/EWS/Exchange.asmx
davmail.mode=O365Interactive
davmail.ssl=false
davmail.imapPort=1144
davmail.smtpPort=1026
davmail.caldavPort=1080
davmail.ldapPort=1389
davmail.keepDelay=30
davmail.allowRemoteConnections=false
davmail.disableUpdateCheck=true
davmail.logFilePath=.davmail/davmail.log
EOF
      fi
    '';

    copyMsmtpConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      cp ${./dotfiles/msmtprc.conf} ~/.msmtprc
      chmod 600 ~/.msmtprc
    '';

  };

  # You can also manage environment variables but you will have to manually
  # source
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/oskar/etc/profile.d/hm-session-vars.sh
  #
  # if you don't want to manage your shell through Home Manager.
  home.sessionVariables = {
    EDITOR = "vim";
    DOTNET_ROOT = "${pkgs.dotnet-sdk_8}";
    LSP_USE_PLISTS = "true";
  };

  # # Enable lorri for easy development environment
  # services.lorri.enable = true;

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Enable man cache. -- Needed for consult-man
  programs.man.generateCaches = true;

  # nixpkgs.config.allowUnfree = true;
}
