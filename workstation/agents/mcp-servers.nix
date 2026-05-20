{
  config,
  pkgs,
  ...
}:
let
  context7-wrapper = pkgs.writeShellScript "context7-mcp" ''
    exec caveman-shrink context7-mcp --api-key "$(cat ${config.sops.secrets."authinfo/context7".path})" "$@"
  '';
  github-mcp-wrapper = pkgs.writeShellScript "github-mcp" ''
    GITHUB_PERSONAL_ACCESS_TOKEN="$(cat ${config.sops.secrets."authinfo/github_pat".path})"
    export GITHUB_PERSONAL_ACCESS_TOKEN
    exec caveman-shrink github-mcp-server stdio "$@"
  '';
  emacsConfig = "${config.xdg.configHome}/emacs";
in
{
  programs.claude-code.settings.mcpServers = {
    "context7" = {
      command = toString context7-wrapper;
      type = "stdio";
    };
    "mcp-nixos" = {
      command = "caveman-shrink";
      args = [ "mcp-nixos" ];
      type = "stdio";
    };
    "github-mcp" = {
      command = toString github-mcp-wrapper;
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
