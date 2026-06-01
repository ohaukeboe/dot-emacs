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
  # Built from source via the upstream flake (PR #265). Tracks the
  # codebase-memory-mcp input pinned in the top-level flake.nix.
  codebase-memory-mcp = inputs.codebase-memory-mcp.packages.${pkgs.system}.default;
  emacsConfig = "${config.xdg.configHome}/emacs";
in
{
  programs.claude-code.enableMcpIntegration = true;
  programs.claude-code.mcpServers = {
    "mcp-nixos" = {
      command = "caveman-shrink";
      args = [ "mcp-nixos" ];
      type = "stdio";
    };
    "github-mcp" = {
      command = toString github-mcp-wrapper;
      type = "stdio";
    };
    "codebase-memory" = {
      command = "caveman-shrink";
      args = [ "${codebase-memory-mcp}/bin/codebase-memory-mcp" ];
      type = "stdio";
    };
    "chrome-devtools" = {
      command = "caveman-shrink";
      args = [
        "chrome-devtools-mcp"
        "--executablePath=${pkgs.chromium}/bin/chromium"
      ];
      type = "stdio";
    };
    "elisp-dev-mcp" = {
      command = "caveman-shrink";
      args = [
        "${emacsConfig}/emacs-mcp-stdio.sh"
        "--init-function=elisp-dev-mcp-enable"
        "--stop-function=elisp-dev-mcp-disable"
        "--server-id=elisp-dev-mcp"
      ];
      type = "stdio";
    };
    "lsp-mcp" = {
      command = "caveman-shrink";
      args = [
        "${emacsConfig}/emacs-mcp-stdio.sh"
        "--init-function=lsp-mcp-enable"
        "--stop-function=lsp-mcp-disable"
        "--server-id=lsp-mcp"
      ];
      type = "stdio";
    };
  };

  # auto_index lives in the server's SQLite config (CBM_CACHE_DIR), not in any
  # declarative file, so flip it via the CLI on activation. Idempotent.
  home.activation.codebaseMemoryAutoIndex = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${codebase-memory-mcp}/bin/codebase-memory-mcp config set auto_index true
  '';
}
