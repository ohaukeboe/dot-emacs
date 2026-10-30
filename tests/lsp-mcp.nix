# The ERT suite of workstation/emacs/packages/lsp-mcp.
#
#   nix build .#test-lsp-mcp -L
#
# Run it after any change to lsp-mcp.el or lsp-mcp-test.el.  The suite guards
# what Nix evaluation cannot see: which major modes count as LSP-enabled, the
# shape of the MCP tool replies, and that every tool registers and unregisters.
#
# The tests stub lsp-mode's requests and use dummy major modes, so the build
# needs no language server and no network.
#
# Deliberately a package rather than a check: it builds an Emacs closure, and
# `nix flake check` runs before every commit.
{
  runCommand,
  emacs,
  emacsPackagesFor,
}:

let
  emacsWithPackages = import ./lib/emacs-with-lsp-mode.nix { inherit emacs emacsPackagesFor; };
in
runCommand "test-lsp-mcp"
  {
    nativeBuildInputs = [ emacsWithPackages ];
  }
  ''
    export HOME="$PWD/home"
    mkdir -p "$HOME"
    export LSP_USE_PLISTS=true

    mkdir -p package
    cp ${../workstation/emacs/packages/lsp-mcp/lsp-mcp.el} package/lsp-mcp.el
    cp ${../workstation/emacs/packages/lsp-mcp/lsp-mcp-test.el} package/lsp-mcp-test.el
    cd package

    # The eglot dependency is soft: loading lsp-mcp must not load eglot.
    if ! emacs -batch -L . -l lsp-mcp.el \
      --eval '(when (featurep (quote eglot)) (error "lsp-mcp loaded eglot"))'; then
      echo "lsp-mcp must load without eglot"
      exit 1
    fi

    if ! emacs -batch -L . -l lsp-mcp-test.el -f ert-run-tests-batch-and-exit; then
      echo "lsp-mcp ERT suite failed (see the report above)"
      exit 1
    fi

    touch "$out"
  ''
