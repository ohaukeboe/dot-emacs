{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.agents.mcp.optIn;

  chrome-devtools-mcp = pkgs.callPackage ./packages/chrome-devtools-mcp.nix { };
  kagimcp = pkgs.callPackage ./packages/kagimcp.nix { src = inputs.kagimcp; };
  mobile-mcp = pkgs.callPackage ./packages/mobile-mcp.nix { };
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

  # Servers a repository has to switch on for Claude Code. Their tool lists and
  # instruction blocks load into every session otherwise, while only a few
  # repositories drive a browser or a phone (spec 007, FR-019). Opencode keeps
  # them on everywhere: it has no per-repository switch.
  optInServers = {
    "mobile-mcp" = mkMcpServer {
      command = "mcp-server-mobile";
      shrink = true;
    };
    "chrome-devtools" = mkMcpServer {
      command = "chrome-devtools-mcp";
      args = [ "--executablePath=${pkgs.chromium}/bin/chromium" ];
      shrink = true;
    };
  };

  # The plugin name sets the tool prefix: mcp__plugin_<plugin>_<server>__*.
  # Keep it distinct from every skill name, since both share ~/.claude/skills.
  pluginNames = {
    "mobile-mcp" = "hm-mobile";
    "chrome-devtools" = "hm-browser";
  };
  pluginName = s: pluginNames.${s};

  # A skills-directory plugin bundling one opt-in server, off by default. A
  # repository enables it with `enabledPlugins."<plugin>@skills-dir" = true` in
  # its .claude/settings.local.json (contracts/mcp-opt-in.md).
  mkOptInPlugin =
    server:
    let
      name = pluginName server;
      s = optInServers.${server};
    in
    pkgs.runCommand "claude-plugin-${name}"
      {
        pluginJson = builtins.toJSON {
          inherit name;
          version = "1.0.0";
          description = "${server} MCP (opt-in per repo)";
          defaultEnabled = false;
        };
        mcpJson = builtins.toJSON {
          mcpServers.${server} = {
            type = "stdio";
            inherit (s) command args;
          };
        };
        passAsFile = [
          "pluginJson"
          "mcpJson"
        ];
      }
      ''
        mkdir -p $out/.claude-plugin
        cp "$pluginJsonPath" $out/.claude-plugin/plugin.json
        cp "$mcpJsonPath" $out/.mcp.json
      '';
in
{
  options.agents.mcp.optIn = {
    servers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.enum [
          "mobile-mcp"
          "chrome-devtools"
        ]
      );
      default = [
        "mobile-mcp"
        "chrome-devtools"
      ];
      description = ''
        MCP servers Claude Code loads only in repositories that enable their
        plugin (hm-mobile, hm-browser). A server left out of this list is on
        in every session, as before.
      '';
    };

    outputTokens = lib.mkOption {
      type = lib.types.ints.between 1000 100000;
      default = 10000;
      description = ''
        MAX_MCP_OUTPUT_TOKENS for Claude Code. A larger MCP text result is
        saved to a file and replaced by its path and a preview.
      '';
    };
  };

  options.agents.claudeSkillsDirPlugins = lib.mkOption {
    type = lib.types.attrsOf lib.types.package;
    default = { };
    internal = true;
    description = ''
      Plugin directories to place in ~/.claude/skills, keyed by plugin name.
      skills.nix links them into the skills directory.
    '';
  };

  config = {
    assertions = [
      {
        # mkOptInPlugin writes command and args only; an env would be dropped.
        assertion = lib.all (s: !(optInServers.${s} ? env)) cfg.servers;
        message = ''
          An MCP server in agents.mcp.optIn.servers sets env, which its plugin's
          .mcp.json cannot carry. In workstation/agents/mcp-servers.nix, drop the
          env from its optInServers entry or remove it from optIn.servers.
        '';
      }
    ];

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
        args = [
          "stdio"
          "--toolsets=default,actions"
        ];
        env.GITHUB_PERSONAL_ACCESS_TOKEN.file = config.sops.secrets."authinfo/github_pat".path;
        shrink = true;
      };
      "codebase-memory" = mkMcpServer {
        command = "${pkgs.codebase-memory-mcp}/bin/codebase-memory-mcp";
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
    }
    // lib.filterAttrs (name: _: !(lib.elem name cfg.servers)) optInServers;

    agents.claudeSkillsDirPlugins = lib.listToAttrs (
      map (s: lib.nameValuePair (pluginName s) (mkOptInPlugin s)) cfg.servers
    );

    # Written out so the default is visible in settings.json. Merges with the
    # enabledPlugins set in default.nix.
    programs.claude-code.settings.enabledPlugins = lib.genAttrs (map (
      s: "${pluginName s}@skills-dir"
    ) cfg.servers) (_: false);

    # Opencode gets the opt-in servers directly, in its local-server shape.
    # Servers not opted out of the global set already reach it through
    # enableMcpIntegration.
    programs.opencode.settings.mcp = lib.mapAttrs (_: s: {
      type = "local";
      command = [ s.command ] ++ s.args;
      enabled = true;
    }) (lib.getAttrs cfg.servers optInServers);

    # The harness saves a larger MCP result to tool-results/ and shows its path
    # and a preview instead. A server can raise its own limit per tool with
    # `_meta."anthropic/maxResultSizeChars"`. As of kagimcp 1.0.2, context7-mcp
    # 4.4.4, chrome-devtools-mcp 1.12.0, mobile-mcp 1.0.12, mcp-nixos 3.0.1,
    # github-mcp-server 1.14.0, codebase-memory-mcp 0.11.0, mcp-server-lib and
    # lsp-mcp, none declares it, so the limit applies to all. Re-check on a
    # version bump: grep -r maxResultSizeChars <package store path>.
    programs.claude-code.settings.env.MAX_MCP_OUTPUT_TOKENS = toString cfg.outputTokens;

    # auto_index lives in the server's SQLite config (CBM_CACHE_DIR), not in any
    # declarative file, so flip it via the CLI on activation. Idempotent.
    # The CLI refuses to start while another CBM process holds the cache with a
    # different build hash — which is exactly the case during a rebuild that
    # updates the server while an editor session still runs the old one. That is
    # not worth failing the whole activation over, so warn and move on; the next
    # activation with no session running sets it.
    home.activation.codebaseMemoryAutoIndex = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${pkgs.codebase-memory-mcp}/bin/codebase-memory-mcp config set auto_index true \
        || warnEcho "codebase-memory-mcp: could not set auto_index (a CBM session is likely running); skipping."
    '';
  };
}
