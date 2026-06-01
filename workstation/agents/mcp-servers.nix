{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  chrome-devtools-mcp = pkgs.callPackage ./packages/chrome-devtools-mcp.nix { };
  kagimcp = pkgs.callPackage ./packages/kagimcp.nix { src = inputs.kagimcp; };
  codebase-memory-mcp = inputs.codebase-memory-mcp.packages.${pkgs.system}.default;
  emacsConfig = "${config.xdg.configHome}/emacs";

  # Wraps an MCP server with optional caveman-shrink token compression and/or
  # secret-env-from-file injection. Returns an attrset shaped for
  # `programs.mcp.servers.<name>`.
  mkMcpServer =
    {
      name,
      command,
      args ? [ ],
      env ? { },
      secretEnvFiles ? { },
      shrink ? false,
    }:
    let
      hasSecrets = secretEnvFiles != { };
      cmdAndArgs = (lib.optional shrink "caveman-shrink") ++ [ command ] ++ args;
      wrapper = pkgs.writeShellScript "${name}-mcp" ''
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (var: path: ''
            ${var}="$(cat ${path})"
            export ${var}
          '') secretEnvFiles
        )}
        exec ${lib.escapeShellArgs cmdAndArgs} "$@"
      '';
    in
    if hasSecrets then
      {
        command = toString wrapper;
      }
      // lib.optionalAttrs (env != { }) { inherit env; }
    else if shrink then
      {
        command = "caveman-shrink";
        args = [ command ] ++ args;
      }
      // lib.optionalAttrs (env != { }) { inherit env; }
    else
      { inherit command args; } // lib.optionalAttrs (env != { }) { inherit env; };

  # Emacs MCP stdio servers all share the same launcher script and arg shape.
  mkEmacsStdioServer =
    {
      name,
      initFunction,
      stopFunction,
      shrink ? true,
    }:
    mkMcpServer {
      inherit name shrink;
      command = "${emacsConfig}/emacs-mcp-stdio.sh";
      args = [
        "--init-function=${initFunction}"
        "--stop-function=${stopFunction}"
        "--server-id=${name}"
      ];
    };
in
{
  programs.mcp.enable = true;
  programs.claude-code.enableMcpIntegration = true;
  programs.opencode.enableMcpIntegration = true;

  home.packages = [
    chrome-devtools-mcp
    pkgs.mcp-nixos
    pkgs.github-mcp-server
  ];

  programs.mcp.servers = {
    "mcp-nixos" = mkMcpServer {
      name = "mcp-nixos";
      command = "mcp-nixos";
      shrink = true;
    };
    "github-mcp" = mkMcpServer {
      name = "github-mcp";
      command = "github-mcp-server";
      args = [ "stdio" ];
      secretEnvFiles.GITHUB_PERSONAL_ACCESS_TOKEN = config.sops.secrets."authinfo/github_pat".path;
      shrink = true;
    };
    "codebase-memory" = mkMcpServer {
      name = "codebase-memory";
      command = "${codebase-memory-mcp}/bin/codebase-memory-mcp";
      shrink = true;
    };
    "chrome-devtools" = mkMcpServer {
      name = "chrome-devtools";
      command = "chrome-devtools-mcp";
      args = [ "--executablePath=${pkgs.chromium}/bin/chromium" ];
      shrink = true;
    };
    "elisp-dev-mcp" = mkEmacsStdioServer {
      name = "elisp-dev-mcp";
      initFunction = "elisp-dev-mcp-enable";
      stopFunction = "elisp-dev-mcp-disable";
    };
    "lsp-mcp" = mkEmacsStdioServer {
      name = "lsp-mcp";
      initFunction = "lsp-mcp-enable";
      stopFunction = "lsp-mcp-disable";
    };
    "kagi" = mkMcpServer {
      name = "kagi";
      command = "${kagimcp}/bin/kagimcp";
      secretEnvFiles.KAGI_API_KEY = config.sops.secrets."authinfo/kagi".path;
    };
  };

  # auto_index lives in the server's SQLite config (CBM_CACHE_DIR), not in any
  # declarative file, so flip it via the CLI on activation. Idempotent.
  home.activation.codebaseMemoryAutoIndex = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${codebase-memory-mcp}/bin/codebase-memory-mcp config set auto_index true
  '';
}
