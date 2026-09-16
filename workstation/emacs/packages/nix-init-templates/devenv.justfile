# devenv drives process-compose itself.  It has no streaming-log mode: `up`
# renders a TUI and writes nothing to a pipe, so a non-terminal caller has to
# start detached and read state back through `devenv processes`.

# Start the service group with the process-compose TUI.
up:
    devenv up

# Start it in the background and return.  What Emacs calls.
up-detached:
    devenv up --detach

# Stop the running group.
down:
    devenv processes down

# List the processes and their states.
status:
    devenv processes list

# Attach to a running group and stream its logs.  Needs a terminal.
attach:
    devenv processes attach

# Logs for one process, e.g. `just logs postgres`.
logs name:
    devenv processes logs {{name}}
