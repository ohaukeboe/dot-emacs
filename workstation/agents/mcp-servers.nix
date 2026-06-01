{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  github-mcp-wrapper = pkgs.writeShellScript "github-mcp" ''
    GITHUB_PERSONAL_ACCESS_TOKEN="$(cat ${config.sops.secrets."authinfo/github_pat".path})"
    export GITHUB_PERSONAL_ACCESS_TOKEN
    exec caveman-shrink github-mcp-server stdio "$@"
  '';
  # Upstream kagisearch/kagimcp built from source. Tracks the kagimcp
  # input pinned in the top-level flake.nix (currently main branch).
  #
  # cfn-lint override: fastmcp's transitive test dep chain
  # (py-key-value-aio → aiobotocore → types-aiobotocore-dynamodb → cfn-lint)
  # has failing integration tests in the pinned nixpkgs revision. Skip
  # cfn-lint's own checks so the chain builds. Remove when nixpkgs ships a fix.
  kagimcpPython = pkgs.python312.override {
    packageOverrides = pyfinal: pyprev: {
      cfn-lint = pyprev.cfn-lint.overridePythonAttrs (_: {
        doCheck = false;
      });
    };
  };
  kagimcp = kagimcpPython.pkgs.buildPythonApplication {
    pname = "kagimcp";
    version = "1.0.0";
    pyproject = true;
    src = inputs.kagimcp;
    build-system = with kagimcpPython.pkgs; [ hatchling ];
    dependencies = with kagimcpPython.pkgs; [
      fastmcp
      pydantic
      urllib3
      python-dateutil
      typing-extensions
    ];
    doCheck = false;
  };
  kagi-mcp-wrapper = pkgs.writeShellScript "kagi-mcp" ''
    KAGI_API_KEY="$(cat ${config.sops.secrets."authinfo/kagi".path})"
    export KAGI_API_KEY
    exec ${kagimcp}/bin/kagimcp "$@"
  '';
  # Built from source via the upstream flake (PR #265). Tracks the
  # codebase-memory-mcp input pinned in the top-level flake.nix.
  codebase-memory-mcp = inputs.codebase-memory-mcp.packages.${pkgs.system}.default;
  emacsConfig = "${config.xdg.configHome}/emacs";
in
{
  programs.mcp.enable = true;
  programs.claude-code.enableMcpIntegration = true;
  programs.opencode.enableMcpIntegration = true;

  programs.mcp.servers = {
    "mcp-nixos" = {
      command = "caveman-shrink";
      args = [ "mcp-nixos" ];
    };
    "github-mcp" = {
      command = toString github-mcp-wrapper;
    };
    "codebase-memory" = {
      command = "caveman-shrink";
      args = [ "${codebase-memory-mcp}/bin/codebase-memory-mcp" ];
    };
    "chrome-devtools" = {
      command = "caveman-shrink";
      args = [
        "chrome-devtools-mcp"
        "--executablePath=${pkgs.chromium}/bin/chromium"
      ];
    };
    "elisp-dev-mcp" = {
      command = "caveman-shrink";
      args = [
        "${emacsConfig}/emacs-mcp-stdio.sh"
        "--init-function=elisp-dev-mcp-enable"
        "--stop-function=elisp-dev-mcp-disable"
        "--server-id=elisp-dev-mcp"
      ];
    };
    "lsp-mcp" = {
      command = "caveman-shrink";
      args = [
        "${emacsConfig}/emacs-mcp-stdio.sh"
        "--init-function=lsp-mcp-enable"
        "--stop-function=lsp-mcp-disable"
        "--server-id=lsp-mcp"
      ];
    };
    "kagi" = {
      command = toString kagi-mcp-wrapper;
    };
  };

  # auto_index lives in the server's SQLite config (CBM_CACHE_DIR), not in any
  # declarative file, so flip it via the CLI on activation. Idempotent.
  home.activation.codebaseMemoryAutoIndex = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${codebase-memory-mcp}/bin/codebase-memory-mcp config set auto_index true
  '';
}
