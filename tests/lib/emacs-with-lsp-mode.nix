# Emacs with lsp-mode and mcp-server-lib, for the ERT suites that load
# lsp-mcp (tests/lsp-mcp.nix, tests/format-on-edit.nix).
#
# lsp-mode is built with plists, as workstation/home.nix builds it: the
# fixtures are plists, and lsp-get on a hash-table build cannot read them.
# mcp-server-lib ships mcp-server-lib-ert, the in-process server the
# tool-registration tests talk to.  Run the suites with LSP_USE_PLISTS=true
# as well.
{ emacs, emacsPackagesFor }:

(emacsPackagesFor emacs).emacsWithPackages (epkgs: [
  (epkgs.lsp-mode.overrideAttrs (p: {
    buildPhase = ''
      export LSP_USE_PLISTS=true;
    ''
    + p.buildPhase;
  }))
  epkgs.mcp-server-lib
])
