{ pkgs, ... }:
{
  packages = [ pkgs.git ];

  # Services start with `devenv up`, never on `direnv` load.
  # services.postgres = {
  #   enable = true;
  #   package = pkgs.postgresql_16;
  #   listen_addresses = "127.0.0.1";
  #   port = 5433;
  #   initialDatabases = [ { name = "dev"; } ];
  # };
}
