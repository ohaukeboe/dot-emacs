# Secrets for this project are explicit-run: they reach the one process that
# asks for them and nothing else.  Nothing here exports into the shell, so
# direnv (and every Emacs subprocess under this directory) stays clean.
#
# Invoke as `just -f secrets.justfile <recipe>`; the kind's own justfile, if
# it has one, is untouched.

file := "secrets.enc.yaml"

# Run a shell command with the secrets in its environment.  The command is
# one argument, so quote it: `just -f secrets.justfile run 'psql -c "\\l"'`.
run cmd:
    sops exec-env {{file}} {{quote(cmd)}}

# Decrypt to stdout.  Prints plaintext -- do not pipe into anything that logs.
show:
    sops -d {{file}}

# Edit the encrypted file in $EDITOR.
edit:
    sops {{file}}
