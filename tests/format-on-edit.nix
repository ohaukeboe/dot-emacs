# The ERT suite of workstation/agents/format-on-edit.el, the Elisp side of
# the Claude Code format-on-edit hook.
#
#   nix build .#test-format-on-edit -L
#
# Run it after any change to format-on-edit.el, format-on-edit-test.el or
# lsp-mcp-enabled-mode-p.  The suite guards what Nix evaluation cannot see:
# that queueing returns at once and Emacs keeps running while a job is in
# flight, that servers start only for LSP-enabled modes in buffers the hook
# opened, that late or superseded formatting is dropped, the cold-server
# budget, and the manifest reminder.
#
# The tests stub the language-server adapters and use dummy major modes, so
# the build needs no language server and no network.
#
# Deliberately a package rather than a check: it builds an Emacs closure, and
# `nix flake check` runs before every commit.
{
  runCommand,
  emacs,
  emacsPackagesFor,
}:

let
  # lsp-mcp is loaded for its LSP-enabled-mode check, and it requires
  # lsp-mode and mcp-server-lib.
  emacsWithPackages = import ./lib/emacs-with-lsp-mode.nix { inherit emacs emacsPackagesFor; };
in
runCommand "test-format-on-edit"
  {
    nativeBuildInputs = [ emacsWithPackages ];
  }
  ''
    export HOME="$PWD/home"
    mkdir -p "$HOME"
    export LSP_USE_PLISTS=true

    mkdir -p package
    cp ${../workstation/emacs/packages/lsp-mcp/lsp-mcp.el} package/lsp-mcp.el
    cp ${../workstation/agents/format-on-edit.el} package/format-on-edit.el
    cp ${../workstation/agents/format-on-edit-test.el} package/format-on-edit-test.el
    cd package

    if ! emacs -batch -L . -l format-on-edit-test.el -f ert-run-tests-batch-and-exit; then
      echo "format-on-edit ERT suite failed (see the report above)"
      exit 1
    fi

    touch "$out"
  ''
