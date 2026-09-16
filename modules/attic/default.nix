{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.modules.attic;
in
{
  options.modules.attic = {
    push.enable = mkEnableOption ''
      pushing locally built store paths to the homestach attic cache.

      Off by default, and deliberately not enabled on the work laptop: the hook
      uploads everything the Nix daemon builds, which on a work machine can
      include dependencies fetched with work credentials. Pulling from the cache
      is configured separately in common/caches.nix and is enabled everywhere.
    '';
  };

  config = mkIf cfg.push.enable {
    # `attic watch-store` is the documented way to do this and it does not work:
    # it detects new paths by watching /nix/store for the removal of
    # `<path>.lock` files, and the Nix on these machines creates no such files.
    #
    # So, a post-build hook — but one that cannot make a build wait on the
    # cache. It hands the paths to a transient systemd unit with --no-block and
    # returns immediately, so a slow or unreachable atticd costs a build nothing
    # and fails nothing. The hook exits 0 whatever happens, because a non-zero
    # exit here fails the build that produced the paths.
    #
    # --no-closure because every path in the closure was itself built here and
    # got its own invocation. Paths signed by an upstream cache key are skipped
    # by attic itself, so substituted paths are not re-uploaded.
    #
    # This mirrors nixos/deepthought/services/attic.nix in the homestach repo;
    # see docs/adr/0012-binary-cache-on-deepthought.md there for the reasoning.
    nix.settings.post-build-hook = pkgs.writeShellScript "attic-push-hook" ''
      set -eu
      [ -n "''${OUT_PATHS:-}" ] || exit 0
      ${pkgs.systemd}/bin/systemd-run \
        --no-block --collect --quiet \
        --property=Environment=HOME=/root \
        ${pkgs.attic-client}/bin/attic push --no-closure homestach $OUT_PATHS \
        || echo "attic: could not queue a push for $OUT_PATHS" >&2
      exit 0
    '';

    # The token carries both push and pull on `homestach`. Pull is not optional
    # even though the cache is public: `get-missing-paths` refuses a token that
    # lacks it rather than treating the request as anonymous.
    sops.secrets."attic/push-token" = {
      sopsFile = ../../sops/system/secrets.yaml;
      key = "attic/push_token";
    };

    # The client reads its token from `$XDG_CONFIG_HOME/attic/config.toml` and
    # from nowhere else — no environment variable, no flag. The hook runs as the
    # Nix daemon, which is root, so /root/.config is where it looks.
    #
    # The endpoint is the public name rather than anything nearer: the client
    # asks the server where the API lives and then talks to that, so atticd's
    # own `api-endpoint` governs the push regardless of what is written here.
    sops.templates."attic-client-config" = {
      content = ''
        default-server = "homestach"

        [servers.homestach]
        endpoint = "https://attic.homestach.eu/"
        token = "${config.sops.placeholder."attic/push-token"}"
      '';
    };

    # A symlink rather than a copy: sops-nix re-renders the template on every
    # activation, and a copy would go stale the first time the token is rotated.
    systemd.tmpfiles.rules = [
      "d /root/.config 0700 root root -"
      "d /root/.config/attic 0700 root root -"
      "L+ /root/.config/attic/config.toml - - - - ${config.sops.templates."attic-client-config".path}"
    ];

    environment.systemPackages = [ pkgs.attic-client ];
  };
}
