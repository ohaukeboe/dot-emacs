{
  description = "A flake with a dev shell and process-compose services";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      # Every system nixpkgs exposes, without a hardcoded list or an extra
      # input. flake-parts needs an explicit list here, so this is the
      # equivalent of mapping over legacyPackages in a plain flake.
      systems = inputs.nixpkgs.lib.systems.flakeExposed;

      imports = [ inputs.process-compose-flake.flakeModule ];

      perSystem =
        {
          self',
          pkgs,
          config,
          ...
        }:
        {
          # Run with `just up`, which enters the project root first: dataDir
          # below is resolved against the working directory, not the flake, so
          # `nix run` from a subdirectory silently creates a second data dir.
          process-compose."services" = {
            imports = [ inputs.services-flake.processComposeModules.default ];

            # services-flake defaults no-server to true, which leaves no API
            # to talk to; `just down`, `status` and `attach` need one.  Turn
            # it on, but over a unix socket rather than the default TCP 8080,
            # which is shared machine-wide.  The socket and log paths are
            # relative, so every checkout gets its own, the same way dataDir
            # does.
            cli.options = {
              no-server = false;
              use-uds = true;
              unix-socket = "./.process-compose.sock";
              log-file = "./.process-compose.log";
            };

            services.postgres."db" = {
              enable = true;
              # Bump per checkout; a second worktree running at the same time
              # collides on the port (the relative dataDir does not).
              port = 5433;
              listen_addresses = "127.0.0.1";
              initialDatabases = [ { name = "dev"; } ];
            };
          };

          packages.default = self'.packages.services;

          devShells.default = pkgs.mkShell {
            # Puts psql and the other enabled services' client tools on PATH.
            inputsFrom = [ config.process-compose."services".services.outputs.devShell ];
            packages = [
              self'.packages.services
              # `just down`, `status` and `attach` drive the running group
              # through the process-compose client, which the generated
              # wrapper does not put on PATH by itself.
              pkgs.process-compose
            ];
          };
        };
    };
}
