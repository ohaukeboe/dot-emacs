{
  inputs,
  lib,
  pkgs,
  config,
  isNixos ? false,
  ...
}:
let
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  system = pkgs.stdenv.system;
in
{
  imports = [
    ./ssh.nix
    inputs.zen-browser.homeModules.beta
    ./calibre
  ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username =
    let
      user = builtins.getEnv "USER";
    in
    if user != "" then user else "oskar";

  home.homeDirectory =
    let
      home = builtins.getEnv "HOME";
    in
    if home != "" then home else "/home/oskar";

  manual.manpages.enable = false;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  # home.stateVersion = "23.05"; # Please read the comment before changing.

  #services.emacs.enable = true;
  programs.emacs = {
    enable = true;
    # package = pkgs.emacs-pgtk;
    package = (
      pkgs.emacsWithPackagesFromUsePackage {
        package = pkgs.emacs-unstable-pgtk;
        config = ./emacs/config.org;
        alwaysEnsure = false;
        alwaysTangle = true;
        extraEmacsPackages =
          epkgs: with epkgs; [
            treesit-grammars.with-all-grammars
            edit-indirect # Edit codeblocks in markdown
            copilot
            jinx
            cdlatex
            auctex
            (lsp-mode.overrideAttrs (p: {
              buildPhase = ''
                export LSP_USE_PLISTS=true;
              ''
              + p.buildPhase;
            }))
            (lsp-ui.overrideAttrs (p: {
              buildPhase = ''
                export LSP_USE_PLISTS=true;
              ''
              + p.buildPhase;
            }))
            (dap-mode.overrideAttrs (p: {
              buildPhase = ''
                export LSP_USE_PLISTS=true;
              ''
              + p.buildPhase;
            }))
            (consult-lsp.overrideAttrs (p: {
              buildPhase = ''
                export LSP_USE_PLISTS=true;
              ''
              + p.buildPhase;
            }))
            (lsp-treemacs.overrideAttrs (p: {
              buildPhase = ''
                export LSP_USE_PLISTS=true;
              ''
              + p.buildPhase;
            }))
            (lsp-java.overrideAttrs (p: {
              buildPhase = ''
                export LSP_USE_PLISTS=true;
              ''
              + p.buildPhase;
            }))
            (lsp-docker.overrideAttrs (p: {
              buildPhase = ''
                export LSP_USE_PLISTS=true;
              ''
              + p.buildPhase;
            }))
          ];
      }
    );
  };

  home.packages = (
    with pkgs;
    lib.lists.flatten [
      wakatime-cli
      # pympress # pdf presenter
      git-crypt

      ### fish ###
      babelfish

      ### misc ###
      sshfs
      phoronix-test-suite
      ltex-ls-plus # languagetool lsp
      packwiz # Minecraft modpack creator utility
      zoxide
      gnuplot
      ditaa
      pkg-config
      neofetch
      gh # github cli
      protonmail-bridge
      davmail # bridge allowing to use exchange through IMAP
      claude-code
      claude-code-acp
      goose-cli
      aider-chat-full # another AI thingy
      opencode
      playwright-mcp
      emacs-lsp-booster
      trash-cli
      w3m # text based web-browser

      ### just ###
      just
      just-lsp

      # git
      ripgrep
      fd

      ### terraform ###
      terraform
      terraform-ls

      ### Reading ###
      rmapi
      (lib.optional (system != "aarch64-linux") zotero)
      inputs.zotra-server.packages.${system}.default

      ### Java ###
      jdk
      maven
      gradle

      ### Kotlin ###
      kotlin
      kotlin-language-server
      inputs.kotlin-lsp.packages.${system}.default

      ### C ###
      man-pages
      man-pages-posix
      gnumake

      clang-tools
      clang
      clang-analyzer
      (lib.hiPrio gcc)
      # Needed hiPrio to resolve conflict as both
      # clang and gcc provide C++ binary
      # ccls
      bear # useful for using clangd

      ### python ###
      uv
      (python313.withPackages (
        ps: with ps; [
          python-lsp-server
          python-lsp-server.optional-dependencies.all
          python-lsp-ruff
          pylsp-mypy

          # I want these globally for use in org-mode
          matplotlib
          scipy
          pandas
        ]
      ))

      ### C# ###
      omnisharp-roslyn

      ### rust ###
      rustup

      ### go ###
      go
      gopls
      golangci-lint-langserver

      ### maude ###
      # maude

      ### plantuml ###
      plantuml
      graphviz

      mermaid-cli

      ### nix ###
      nil # lsp
      nixfmt-rfc-style

      ### latex org ###
      texlive.combined.scheme-full

      # org-inline-pdf
      pdf2svg
      imagemagick
      # org-download
      wl-clipboard
      # pandoc
      pandoc
      marksman
      # readability-cli
      # sqlite3
      sqlite

      enchant
      hunspellDicts.en_US
      hunspellDicts.nb_NO

      ### node ###
      nodePackages_latest.vscode-langservers-extracted
      nodejs
      nodePackages.typescript-language-server
      typescript
      eslint

      ## mu4e (email)
      mu
      msmtp
      isync

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
      nerd-fonts.roboto-mono
      nerd-fonts.symbols-only
      noto-fonts-color-emoji
    ]
    ++ lib.optionals isLinux (
      lib.lists.flatten [
        # Use script at https://github.com/FlyinPancake/1password-flatpak-browser-integration with zen flatpak instead
        # zen-browser.packages."${system}".default # for 1password to work, add '.zen-wrapped' to '/etc/1password/custom_allowed_browsers'

        vlc
        # python313Packages.weasyprint # website to pdf converter. Seems to be broken on mac
        tailscale

        ### nixGL ###
        (lib.optional (!isNixos) pkgs.nixgl.nixVulkanIntel)
        # nixgl.auto.nixVulkanNvidia

        ### zsa keyboard ###
        zsa-udev-rules
        # keymapp

        ### C ###
        gdb
        valgrind # is broken on darwin
      ]
    )
    ++ lib.optionals isDarwin (
      lib.lists.flatten [
        coreutils # gets the gnu coreutils. Needed for ls --group-directories-first
        pngpaste

        # Not installing python on Linux as I have experienced conflicts
        # on ublue which include python already
        python313
        (with python313Packages; [
          pip
          python-lsp-server
          python-lsp-server.optional-dependencies.all
          matplotlib
          scipy
        ])
      ]
    )
  );

  programs = {
    starship.enable = true;
    bat.enable = true;
    tealdeer = {
      enable = true;
      enableAutoUpdates = true;
      settings.updates.auto_update = true;
    };
    zoxide.enable = true;
    atuin = {
      enable = true;
      daemon.enable = true;
    };
    nix-index.enable = true;
    nix-index.enableFishIntegration = true;

    zen-browser.enable = true;

    # I mostly use fish, but since nix-shell uses bash it is nice to
    # also have it be managed by nix
    bash = {
      enable = true;
    };

    fish = {
      enable = true;
      interactiveShellInit = ''
        set fish_greeting # Disable greeting
      '';

      functions = {
        gitignore = "curl -sL https://www.gitignore.io/api/$argv";
      };

      shellAliases = {
        hs = "home-manager switch --flake .#default --impure -b backup";
        edit = "emacsclient -r -n";
      };

      shellInit = ''
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish' ]
          . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish'
        end

        if [ -e '/opt/homebrew/bin' ]
           fish_add_path /opt/homebrew/bin
        end

        fish_add_path ~/.local/bin/
        fish_add_path ~/.cargo/bin/
      '';

      shellInitLast = ''
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

    chromium = lib.mkIf isLinux {
      enable = true;
      extensions = [
        "aeblfdkhhhdcdjpifhhbdiojplfjncoa" # 1password
      ];
    };
  };

  services.flatpak = {
    enable = isNixos;
    overrides = {
      global = {
        Environment = {
          # Fix un-themed cursor in some Wayland apps
          XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons";
        };
      };
    };

    update.auto = {
      enable = true;
      onCalendar = "weekly";
    };

    packages = [
      "com.github.tchx84.Flatseal"
    ];
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
    ".authinfo".source = ../secrets/.authinfo;
    ".mbsyncrc".source = ./dotfiles/mbsyncrc.conf;
    ".wakatime.cfg".source = ../secrets/wakatime.cfg;
    ".aws/config".source = ../secrets/aws.config;
    ".config/scw/config.yaml".source = ../secrets/scaleway.yaml;

    "${config.xdg.configHome}/agents/AGENTS.md".source = ./agents-global.md;
    "${config.xdg.configHome}/opencode/AGENTS.md".source = ./agents-global.md;
    "${config.xdg.configHome}/claude/CLAUDE.md".source = ./agents-global.md;

    "${config.xdg.configHome}/opencode/opencode.json" = {
      text = builtins.toJSON {
        "$schema" = "https://opencode.ai/config.json";
        model = "openrouter/anthropic/claude-sonnet-4.5";
      };
    };

    ".local/share/ditaa/ditaa.jar".source = "${pkgs.ditaa}/lib/ditaa.jar";

    # Emacs
    "${config.xdg.configHome}/emacs/init.el".source = ./emacs/init.el;
    "${config.xdg.configHome}/emacs/special-symbols.el".source = ./emacs/special-symbols.el;
    "${config.xdg.configHome}/emacs/config.org".source = ./emacs/config.org;
    "${config.xdg.configHome}/emacs/packages/" = {
      source = ./emacs/packages;
      recursive = true;
    };

    ".aider.conf.yml".source = (pkgs.formats.yaml { }).generate "aider-conf" {
      cache-prompts = true;
      cache-keepalive-pings = 5;
      code-theme = "monokai";
      auto-commits = false;
      model = "openrouter/anthropic/claude-sonnet-4.5";
      weak-model = "openrouter/anthropic/claude-haiku-4.5";
    };
  };

  # Only create initial config if it doesn't exist
  home.activation = {
    starshipConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.starship}/bin/starship preset nerd-font-symbols > $HOME/.config/starship.toml
    '';

    createDavmailConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -f $HOME/.davmail.properties ]; then
        $DRY_RUN_CMD cp ${./dotfiles/davmail.properties} $HOME/.davmail.properties
      fi
      $DRY_RUN_CMD chmod 664 $HOME/.davmail.properties
    '';

    copyMsmtpConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD cp ${./dotfiles/msmtprc.conf} $HOME/.msmtprc
      $DRY_RUN_CMD chmod 600 $HOME/.msmtprc
    '';
  };

  programs.git = {
    enable = true;

    settings = {
      user = {
        name = "Oskar Haukebøe";
        signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILToVl9RmOhn1TaQHiDPIS1/TGbHeA6ssTTocJmv5Yvf";
      };

      init.defaultBranch = "main";
      github.user = "ohaukeboe";
      gitlab.user = "ohaukeboe";
      "github \"github.uio.no/api/v3\"".user = "oskah";
      "gitea \"codeberg.org/api/v1\"".user = "ohaukeboe";
      "github \"api.github.uio.no\"".user = "oskah";

      core = {
        preloadindex = true;
        fscache = true;
      };

      log.decorate = "full";
      gc.auto = 256;

      gpg.format = "ssh";
      commit.gpgsign = true;
      credential.helper = "store";
      "gpg \"ssh\"".program =
        if isLinux then
          "${pkgs._1password-gui}/bin/op-ssh-sign"
        else
          "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";

    };

    includes = [
      {
        contents.user = {
          email = "ohaukeboe@pm.me";
        };
      }
      {
        condition = "gitdir:**/knowit/**/.git";
        contents.user = {
          email = "oskar.haukeboe@knowit.no";
        };
      }
    ];

    maintenance = {
      enable = true;
      repositories = [
        "~/projects/*"
        "~/knowit/*"
      ];
    };
  };

  xdg.mimeApps = {
    enable = isLinux;
    defaultApplications = {
      "text/html" = "zen-beta.desktop";
      "x-scheme-handler/http" = "zen-beta.desktop";
      "x-scheme-handler/https" = "zen-beta.desktop";
      "x-scheme-handler/about" = "zen-beta.desktop";
      "x-scheme-handler/unknown" = "zen-beta.desktop";
      "application/pdf" = "zen-beta.desktop";
    };
  };

  home.sessionVariables = {
    EDITOR = "vim";
    LSP_USE_PLISTS = "true";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Enable man cache. -- Needed for consult-man
  programs.man.generateCaches = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
