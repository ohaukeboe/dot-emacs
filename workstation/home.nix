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
  system = pkgs.stdenv.hostPlatform.system;

  # $EDITOR wrapper: reuse the current Emacs frame when launched from a
  # terminal living inside Emacs (vterm or ghostel); otherwise pop a fresh
  # frame. INSIDE_EMACS is "<version>,vterm" for vterm and "ghostel" for
  # ghostel.
  emacsEditor = pkgs.writeShellScript "emacs-editor" ''
    case "$INSIDE_EMACS" in
      *vterm*|*ghostel*)
        exec ${config.programs.emacs.finalPackage}/bin/emacsclient "$@" ;;
      *)
        exec ${config.programs.emacs.finalPackage}/bin/emacsclient -c -a "" "$@" ;;
    esac
  '';
in
{
  imports = [
    ./ssh.nix
    ./sops.nix
    ./agents
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
          epkgs:
          with epkgs;
          let
            # Shared so lsp-ltex-plus reuses the exact same derivation and we
            # don't end up with two lsp-mode copies of the same version.
            lspModePlist = lsp-mode.overrideAttrs (p: {
              buildPhase = ''
                export LSP_USE_PLISTS=true;
              ''
              + p.buildPhase;
            });
          in
          [
            treesit-grammars.with-all-grammars
            edit-indirect # Edit codeblocks in markdown
            copilot
            jinx
            cdlatex
            auctex
            lspModePlist
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

            # Packages previously installed via use-package :vc, now built from
            # source. The branch-HEAD ones (claude-code-ide, gptel-quick,
            # consult-mu) are flake inputs advancing on `nix flake update`; the
            # version-pinned ones (pgmacs, lsp-ltex-plus) come from nvfetcher
            # (pkgs.nvSources) and move on `just update-sources`.
            (epkgs.trivialBuild {
              pname = "claude-code-ide";
              version = inputs.claude-code-ide-src.shortRev or "unstable";
              src = inputs.claude-code-ide-src;
              packageRequires = [
                websocket
                transient
                web-server
              ];
            })
            (epkgs.trivialBuild {
              pname = "gptel-quick";
              version = inputs.gptel-quick-src.shortRev or "unstable";
              src = inputs.gptel-quick-src;
              packageRequires = [
                compat
                gptel
              ];
            })
            (epkgs.trivialBuild {
              pname = "consult-mu";
              version = inputs.consult-mu-src.shortRev or "unstable";
              src = inputs.consult-mu-src;
              packageRequires = [
                consult
                embark
                mu4e
              ];
            })
            (epkgs.trivialBuild {
              pname = "pgmacs";
              version = pkgs.nvSources.pgmacs.version;
              src = pkgs.nvSources.pgmacs.src;
              packageRequires = [ pg ];
            })
            (epkgs.trivialBuild {
              pname = "lsp-ltex-plus";
              version = pkgs.nvSources.lsp-ltex-plus.version;
              src = pkgs.nvSources.lsp-ltex-plus.src;
              packageRequires = [ lspModePlist ];
            })
          ];
      }
    );
  };

  home.packages = (
    with pkgs;
    lib.lists.flatten [
      # pympress # pdf presenter
      git-crypt

      ### fish ###
      babelfish

      ### misc ###
      ripgrep
      fd
      dragon-drop # drag-andn-drop from terminal
      screen
      tmux
      sshfs
      ltex-ls-plus # languagetool lsp
      zoxide
      gnuplot
      ditaa
      pkg-config
      fastfetch
      gh # github cli
      emacs-lsp-booster
      trash-cli
      winboat
      yaml-language-server
      ### just ###
      just
      just-lsp

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
      (pkgs.callPackage "${inputs.kotlin-lsp}/package.nix" { })

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

      (lib.optionals isLinux (
        with pkgs;
        [
          gdb
          valgrind # is broken on darwin
        ]
      ))

      ### python ###
      uv
      ty
      (python313.withPackages (
        ps: with ps; [
          python-lsp-server
          python-lsp-ruff

          # I want these globally for use in org-mode
          matplotlib
          scipy
          pandas
          pandas-stubs
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
      nixfmt
      nixd

      ### latex org ###
      texlive.combined.scheme-full

      ## org-inline-pdf
      pdf2svg
      imagemagick
      ghostscript
      ## org-download
      wl-clipboard
      ## pandoc
      pandoc
      marksman
      # readability-cli
      # sqlite3
      sqlite

      enchant
      hunspellDicts.en_US
      hunspellDicts.nb_NO

      ### node ###
      nodejs
      typescript
      typescript-language-server

      ## mu4e (email)
      mu
      msmtp
      isync
      protonmail-bridge
      davmail # bridge allowing to use exchange through IMAP
      w3m # text based web-browser

      ### fonts ###
      nerd-fonts.roboto-mono
      nerd-fonts.symbols-only
      noto-fonts-color-emoji
    ]
    ++ lib.optionals isLinux (
      lib.lists.flatten [
        vlc
        # python313Packages.weasyprint # website to pdf converter. Seems to be broken on mac
        tailscale

        ### nixGL ###
        (lib.optional (!isNixos) pkgs.nixgl.nixVulkanIntel)
        # nixgl.auto.nixVulkanNvidia

        ### zsa keyboard ###
        zsa-udev-rules
        # keymapp
      ]
    )
    ++ lib.optionals isDarwin (
      lib.lists.flatten [
        coreutils # gets the gnu coreutils. Needed for ls --group-directories-first
        pngpaste
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

        # Set EDITOR here, not via home.sessionVariables: a shell spawned inside
        # an already-running Emacs (vterm/ghostel buffer) inherits the exported
        # __HM_SESS_VARS_SOURCED guard, so hm-session-vars.fish short-circuits
        # and never re-exports EDITOR. This runs unconditionally, every shell.
        set -gx EDITOR ${emacsEditor}

        # make fish update fish_complete_path when XDG_DATA_DIRS
        # changes. This is necessary to make fish apply shell
        # completions from direnv. This will not be necessary anymore
        # when https://github.com/direnv/direnv/issues/1539 is merged
        function __direnv_update_fish_complete_path --on-variable XDG_DATA_DIRS
          for dir in (string split ':' -- $XDG_DATA_DIRS)
            set -l completions_dir "$dir/fish/vendor_completions.d"
            if test -d "$completions_dir"
              if not contains -- "$completions_dir" $fish_complete_path
                set -g fish_complete_path $fish_complete_path $completions_dir
              end
            end
          end
        end
      '';
    };

    direnv = {
      enable = true;
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
    ".mbsyncrc".source = ./dotfiles/mbsyncrc.conf;
    ".aws/config".source = ../secrets/aws.config;
    ".config/scw/config.yaml".source = ../secrets/scaleway.yaml;
    ".screenrc".text = "termcapinfo xterm*|rxvt*|kterm*|Eterm*|vterm* ti@:te@";

    ".local/share/ditaa/ditaa.jar".source = "${pkgs.ditaa}/lib/ditaa.jar";

    # Emacs
    "${config.xdg.configHome}/emacs/init.el".source = ./emacs/init.el;
    "${config.xdg.configHome}/emacs/special-symbols.el".source = ./emacs/special-symbols.el;
    "${config.xdg.configHome}/emacs/config.org".source = ./emacs/config.org;
    "${config.xdg.configHome}/emacs/packages/" = {
      source = ./emacs/packages;
      recursive = true;
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
    signing.format = null; # openpgp

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
    EDITOR = "${emacsEditor}";
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
