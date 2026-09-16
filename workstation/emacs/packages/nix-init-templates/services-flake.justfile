# Services resolve their dataDir and socket against the working directory,
# not the flake, so `nix run` from a subdirectory silently creates a second
# set of state.  just always enters the justfile's own directory before
# running a recipe, which is why upstream recommends driving services
# through it.

socket := "./.process-compose.sock"

# Start the service group with the process-compose TUI.
up:
    nix run .#services

# Start it with plain streaming logs, for a non-terminal caller like Emacs.
up-headless:
    PC_DISABLE_TUI=1 nix run .#services

# Start it in the background and return.
up-detached:
    nix run .#services -- --detached

# Stop the running group.
down:
    process-compose down -U -u {{socket}}

# List the processes and their states.
status:
    process-compose process list -U -u {{socket}}

# Attach the TUI to an already-running group.  Needs a terminal.
attach:
    process-compose attach -U -u {{socket}}

# Open a psql shell against the scaffolded postgres instance.
psql:
    nix develop -c psql -h 127.0.0.1 -p 5433 dev
