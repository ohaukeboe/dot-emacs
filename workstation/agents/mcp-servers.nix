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
  mobile-mcp = pkgs.callPackage ./packages/mobile-mcp.nix { };
  codebase-memory-mcp =
    inputs.codebase-memory-mcp.packages.${pkgs.stdenv.hostPlatform.system}.default;
  emacsConfig = "${config.xdg.configHome}/emacs";

  # Wraps an MCP server with optional caveman-shrink token compression. Returns
  # an attrset shaped for `programs.mcp.servers.<name>`.
  #
  # Secrets go in `env` as file references (`env.VAR.file = <path>`), which
  # upstream handles per consumer: programs.claude-code runs the server through
  # a generated wrapper that reads the file at startup (lib.hm.mcp
  # .wrapEnvFilesCommand), programs.opencode emits a `{file:...}` token the
  # client resolves itself. Either way the value never reaches the store.
  mkMcpServer =
    {
      command,
      args ? [ ],
      env ? { },
      shrink ? false,
    }:
    {
      command = if shrink then "caveman-shrink" else command;
      args = (lib.optional shrink command) ++ args;
    }
    // lib.optionalAttrs (env != { }) { inherit env; };

  # Emacs MCP stdio servers all share the same launcher script and arg shape.
  mkEmacsStdioServer =
    {
      name,
      initFunction,
      stopFunction,
      shrink ? true,
    }:
    mkMcpServer {
      inherit shrink;
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
    mobile-mcp
    pkgs.mcp-nixos
    pkgs.github-mcp-server
    pkgs.context7-mcp
  ];

  programs.mcp.servers = {
    "mcp-nixos" = mkMcpServer {
      command = "mcp-nixos";
      shrink = true;
    };
    "github-mcp" = mkMcpServer {
      command = "github-mcp-server";
      args = [ "stdio" ];
      env.GITHUB_PERSONAL_ACCESS_TOKEN.file = config.sops.secrets."authinfo/github_pat".path;
      shrink = true;
    };
    "codebase-memory" = mkMcpServer {
      command = "${codebase-memory-mcp}/bin/codebase-memory-mcp";
      shrink = true;
    };
    "chrome-devtools" = mkMcpServer {
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
    "mobile-mcp" = mkMcpServer {
      command = "mcp-server-mobile";
      shrink = true;
    };
    "context7" = mkMcpServer {
      command = "context7-mcp";
      args = [
        "--transport"
        "stdio"
      ];
      env.CONTEXT7_API_KEY.file = config.sops.secrets."authinfo/context7".path;
    };
    "kagi" = mkMcpServer {
      command = "${kagimcp}/bin/kagimcp";
      env.KAGI_API_KEY.file = config.sops.secrets."authinfo/kagi".path;
    };
  };

  # auto_index lives in the server's SQLite config (CBM_CACHE_DIR), not in any
  # declarative file, so flip it via the CLI on activation. Idempotent.
  # The CLI refuses to start while another CBM process holds the cache with a
  # different build hash — which is exactly the case during a rebuild that
  # updates the server while an editor session still runs the old one. That is
  # not worth failing the whole activation over, so warn and move on; the next
  # activation with no session running sets it.
  home.activation.codebaseMemoryAutoIndex = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${codebase-memory-mcp}/bin/codebase-memory-mcp config set auto_index true \
      || warnEcho "codebase-memory-mcp: could not set auto_index (a CBM session is likely running); skipping."
  '';
}
