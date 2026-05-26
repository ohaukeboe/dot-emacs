{
  config,
  pkgs,
  ...
}:
let
  github-mcp-wrapper = pkgs.writeShellScript "github-mcp" ''
    GITHUB_PERSONAL_ACCESS_TOKEN="$(cat ${config.sops.secrets."authinfo/github_pat".path})"
    export GITHUB_PERSONAL_ACCESS_TOKEN
    exec caveman-shrink github-mcp-server stdio "$@"
  '';
  emacsConfig = "${config.xdg.configHome}/emacs";
in
{
  programs.claude-code.settings.mcpServers = {
    "mcp-nixos" = {
      command = "caveman-shrink";
      args = [ "mcp-nixos" ];
      type = "stdio";
    };
    "github-mcp" = {
      command = toString github-mcp-wrapper;
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
}
