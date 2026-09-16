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
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

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
            packages = [ self'.packages.services ];
          };
        };
    };
}
