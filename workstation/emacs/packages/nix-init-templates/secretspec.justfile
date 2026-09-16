# Secrets for this project are explicit-run: they reach the one process that
# asks for them and nothing else.  Nothing here exports into the shell, so
# direnv (and every Emacs subprocess under this directory) stays clean.
#
# Invoke as `just -f secrets.justfile <recipe>`; the kind's own justfile, if
# it has one, is untouched.

# Run a shell command with the secrets in its environment.  The command is
# one argument, so quote it: `just -f secrets.justfile run 'psql -c "\\l"'`.
run cmd:
    secretspec run -- sh -c {{quote(cmd)}}

# Report which declared secrets the provider can supply, prompting for any
# that are missing and writing them back.
check:
    secretspec check

# Set one secret's value.
set name:
    secretspec set {{name}}
