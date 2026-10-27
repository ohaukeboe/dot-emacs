{
  description = "Home Manager configuration of oskar";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    # Official channel tarball instead of github: zstd-compressed (~20% smaller),
    # no GitHub rate limits, IPv6, ships the command-not-found database.
    # https://discourse.nixos.org/t/psa-use-nixos-org-tarballs-for-your-flake-inputs/79950
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Add emacs-overlay
    emacs-overlay = {
      url = "github:nix-community/emacs-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flatpaks.url = "github:gmodena/nix-flatpak/?ref=latest";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };

    # Newer than lanzaboote's pin, which still uses deprecated stdenv.isLinux.
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk partitioning, used by machines provisioned after the
    # first three. See lib/disk-layouts/luks-btrfs.nix and docs/new-machine.md.
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # for list of hardware modules: https://github.com/NixOS/nixos-hardware#list-of-profiles
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Plymouth boot splash theme (modules/silent-boot). No releases upstream,
    # so track HEAD; import only its package.nix to keep flake-utils out.
    mac-style-plymouth = {
      url = "github:SergioRibera/s4rchiso-plymouth-theme";
      flake = false;
    };

    # Add nixGL for better OpenGL and vulkan support
    nixgl.url = "github:nix-community/nixGL";

    # Make apps show in spotlight
    mac-app-util.url = "github:hraban/mac-app-util";

    treefmt-nix.url = "github:numtide/treefmt-nix";

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    kotlin-lsp = {
      url = "github:ohaukeboe/kotlin-lsp-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Proton Pass quick-access popup for COSMIC, enabled by modules/cosmic-de.
    cosmic-pass = {
      url = "github:ohaukeboe/cosmic-pass";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    humanizer-skill = {
      url = "github:blader/humanizer";
      flake = false;
    };

    anthropics-skills = {
      url = "github:anthropics/skills";
      flake = false;
    };

    caveman = {
      url = "github:JuliusBrussee/caveman";
      flake = false;
    };

    cavekit = {
      url = "github:JuliusBrussee/cavekit";
      flake = false;
    };

    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    llm-skills = {
      url = "github:descoped/llm-skills";
      flake = false;
    };

    anthropic-cybersecurity-skills = {
      url = "github:mukul975/Anthropic-Cybersecurity-Skills";
      flake = false;
    };

    understand-anything = {
      url = "github:Lum1104/Understand-Anything";
      flake = false;
    };

    privacy-data-protection-skills = {
      url = "github:mukul975/privacy-data-protection-skills";
      flake = false;
    };

    # git+https, not github: — the org's SAML SSO makes the GitHub API 403 on
    # tokens not authorized for it (docs/adr/0007-saml-sso-github-sources.md).
    punkt-skills = {
      url = "git+https://github.com/oslokommune/punkt-skills";
      flake = false;
    };

    trailofbits-skills = {
      url = "github:trailofbits/skills";
      flake = false;
    };

    kagimcp = {
      url = "github:kagisearch/kagimcp";
      flake = false;
    };

    # No releases; track HEAD. Built by workstation/agents/packages/claude-pointer.nix.
    claude-pointer = {
      url = "github:ohaukeboe/claude-pointer";
      flake = false;
    };

    # No releases or tags; track HEAD. Needs its translation-server submodule.
    # Built by workstation/packages/zotra-server.nix.
    zotra-server = {
      url = "git+https://github.com/mpedramfar/zotra-server?submodules=1";
      flake = false;
    };

    # No releases; track HEAD. Built by workstation/packages/rm-push.nix.
    rm-push = {
      url = "github:ohaukeboe/rm-push";
      flake = false;
    };

    # Emacs packages previously installed via use-package :vc
    claude-code-ide-src = {
      url = "github:manzaltu/claude-code-ide.el";
      flake = false;
    };

    gptel-quick-src = {
      url = "github:karthink/gptel-quick";
      flake = false;
    };

    consult-mu-src = {
      url = "github:armindarvish/consult-mu";
      flake = false;
    };

    # kotlin-ts-mode queries nodes that only exist on the grammar's master;
    # the last release (0.3.8, shipped by nixpkgs) predates them.
    tree-sitter-kotlin-src = {
      url = "github:fwcd/tree-sitter-kotlin";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      emacs-overlay,
      flatpaks,
      nixgl,
      mac-app-util,
      treefmt-nix,
      lanzaboote,
      nixos-hardware,
      nix-index-database,
      ...
    }@inputs:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      # Helper function to generate attributes for each system
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });
      # Attributes that only exist for the Linux systems.
      onLinux = system: nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "linux" system);
      expiringOverrideLib = import ./lib/expiring-override.nix { inherit (nixpkgs) lib; };

      treefmtEval = forAllSystems (system: treefmt-nix.lib.evalModule nixpkgsFor.${system} ./treefmt.nix);

      private = builtins.fromJSON (builtins.readFile "${self}/private/hosts.json");

      defaultConfig =
        {
          "x86_64-linux" = "oskar@x86_64-linux";
          "aarch64-linux" = "oskar@aarch64-linux";
          "aarch64-darwin" = "oskar@aarch64-darwin";
        }
        ."${builtins.currentSystem}";

      # Function to create home-manager configuration for a system
      mkHomeConfiguration = import ./lib/mkHomeConfiguration.nix {
        inherit
          inputs
          nixpkgs
          home-manager
          emacs-overlay
          nixgl
          mac-app-util
          flatpaks
          private
          nix-index-database
          ;
      };

      # Function to create NixOS configuration for a machine
      mkNixosConfiguration = import ./lib/mkNixosConfiguration.nix {
        inherit
          inputs
          nixpkgs
          home-manager
          emacs-overlay
          flatpaks
          lanzaboote
          nix-index-database
          private
          ;
      };

      # Machine definitions
      machines = import ./machines/machines.nix { };

      # The installer entrypoint: `nix run github:ohaukeboe/dot-emacs#install`
      # from a NixOS installer. See scripts/installer.sh and docs/new-machine.md.
      # Nothing here touches `private`, so it evaluates while private/** is still
      # ciphertext, which it always is on a machine that has not bootstrapped.
      installerFor =
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        pkgs.writeShellApplication {
          name = "dot-emacs-install";
          runtimeInputs = with pkgs; [
            git
            just
            vim
          ];
          text = builtins.readFile ./scripts/installer.sh;
        };

      # Reports whether the nixpkgs fix behind each fix reference has reached
      # the pinned nixpkgs. Run by hand: `just check-fixes`. Needs network, so
      # it is an app; its tests are a check. See scripts/check-fixes.sh.
      checkFixesFor =
        system:
        let
          pkgs = nixpkgsFor.${system};
        in
        pkgs.writeShellApplication {
          name = "check-fixes";
          runtimeInputs = with pkgs; [
            coreutils
            curl
            gawk
            git
            gnugrep
            gnused
            jq
          ];
          # The fix reference syntax has one definition, in the library.
          text =
            builtins.replaceStrings [ "@fixReferencePattern@" ] [ expiringOverrideLib.fixReferencePattern ]
              (builtins.readFile ./scripts/check-fixes.sh);
        };
    in
    {
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      nixosConfigurations = nixpkgs.lib.mapAttrs (
        hostname: config: mkNixosConfiguration (config // { inherit hostname; })
      ) machines;

      homeConfigurations = {
        "oskar@x86_64-linux" = mkHomeConfiguration "x86_64-linux";
        "oskar@aarch64-linux" = mkHomeConfiguration "aarch64-linux";
        "oskar@aarch64-darwin" = mkHomeConfiguration "aarch64-darwin";
        "oskar" = self.homeConfigurations.${defaultConfig};
        "default" = self.homeConfigurations.${defaultConfig};
      };

      packages = forAllSystems (
        system:
        {
          default = self.homeConfigurations."oskar@${system}".activationPackage;
          check-fixes = checkFixesFor system;
        }
        # Deliberately a package rather than a check: `nix flake check` runs
        # before every commit and a VM test would add minutes to that loop.
        #   nix build .#test-disk-layout -L
        // onLinux system {
          test-disk-layout = nixpkgsFor.${system}.callPackage ./tests/disk-layout.nix {
            diskoLib = inputs.disko.lib;
          };
          # The ERT suite of workstation/emacs/packages/beads.el; see the file.
          # A package rather than a check because it builds an Emacs closure.
          #   nix build .#test-beads -L
          test-beads = nixpkgsFor.${system}.callPackage ./tests/beads.nix { };
          # The ERT suite of workstation/emacs/packages/walkthrough.el; see the
          # file. A package for the same reason as test-beads.
          #   nix build .#test-walkthrough -L
          test-walkthrough = nixpkgsFor.${system}.callPackage ./tests/walkthrough.nix { };
          # The ERT suite of workstation/emacs/packages/agent-commit-gate.el;
          # see the file. A package for the same reason as test-beads.
          #   nix build .#test-agent-commit-review -L
          test-agent-commit-review = nixpkgsFor.${system}.callPackage ./tests/agent-commit-review.nix { };
          # Regression test for the sops.el save hang; see the file and
          # common/emacs-sops-fix-overlay.nix.
          #   nix build .#test-emacs-sops-save -L
          # Needs the overlays, which live outside nixpkgsFor. emacs-overlay
          # gives the same sops build the configs deploy.
          test-emacs-sops-save =
            (import nixpkgs {
              inherit system;
              overlays = [
                emacs-overlay.overlay
                (import ./common/emacs-sops-fix-overlay.nix)
                (import ./common/expiring-override-overlay.nix)
              ];
            }).callPackage
              ./tests/emacs-sops-save.nix
              { };
          installer = installerFor system;
        }
      );

      apps = forAllSystems (
        system:
        {
          check-fixes = {
            type = "app";
            program = nixpkgs.lib.getExe self.packages.${system}.check-fixes;
            meta.description = "Report whether the fix behind each fix reference reached the pinned nixpkgs";
          };
        }
        // onLinux system {
          install = {
            type = "app";
            program = nixpkgs.lib.getExe self.packages.${system}.installer;
            meta.description = "Install a NixOS machine from this flake, from the installer ISO";
          };
        }
      );

      checks = forAllSystems (
        system:
        {
          formatting = treefmtEval.${system}.config.build.check self;
          # Pure evaluation; see the file.
          expiring-override = nixpkgsFor.${system}.callPackage ./tests/expiring-override.nix { };
          # The agent commit gate against fixture repositories; see the file.
          agent-commit-gate = nixpkgsFor.${system}.callPackage ./tests/agent-commit-gate.nix { };
          # The context status line; see the file.
          context-statusline = nixpkgsFor.${system}.callPackage ./tests/context-statusline.nix {
            caveman-src = inputs.caveman;
          };
          # rtk is unfree (BUSL-1.1); `nixpkgsFor` has no unfree predicate.
          rtk-banner = nixpkgsFor.${system}.callPackage ./tests/rtk-banner.nix {
            rtk =
              (import nixpkgs {
                inherit system;
                config.allowUnfreePredicate = import ./common/unfree-predicates.nix { inherit (nixpkgs) lib; };
              }).rtk;
          };
          # The check-fixes app against a fixture repo and file:// API; see the
          # file. Building the app also shellchecks it.
          check-fixes = nixpkgsFor.${system}.callPackage ./tests/check-fixes.nix {
            check-fixes = self.packages.${system}.check-fixes;
          };
        }
        # writeShellApplication runs shellcheck at build time.
        // onLinux system {
          installer = self.packages.${system}.installer;
        }
      );
    };
}
