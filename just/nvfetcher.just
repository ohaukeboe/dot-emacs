# Source management with nvfetcher
# Version-pinned external sources live in nvfetcher.toml and are generated
# into _sources/generated.nix, consumed via the pkgs.nvSources overlay.

# Regenerate _sources/ from nvfetcher.toml (nodejs is needed for the npm `src.cmd` entries)
update-sources:
    nix-shell -p nvfetcher nodejs --run "nvfetcher -c nvfetcher.toml -o _sources"
