# `config' is unused until a secrets backend is added, at which point declared
# secrets appear as `config.secretspec.secrets.<NAME>'.
{ pkgs, config, ... }:
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

  # Assigning a secret into `env' exports it on shell entry, which devenv's
  # own documentation recommends against: it reaches every process in the
  # shell, not the one that needs it.  Prefer
  # `just -f secrets.justfile run -- <command>'.
  #
  # env.DATABASE_URL = config.secretspec.secrets.DATABASE_URL or "";
}
