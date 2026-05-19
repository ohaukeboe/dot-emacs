{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  newline = pkgs.writeText "newline" "\n";
  combinedDocs = pkgs.concatText "agents-docs.md" (
    [ ./agents-global.md ]
    ++ lib.optionals (config.agents.extraClaudeDocs != [ ]) (
      [ newline ] ++ config.agents.extraClaudeDocs
    )
  );
  claudeDocs = pkgs.concatText "claude-docs.md" (
    [ combinedDocs ]
    ++ lib.optionals (config.agents.extraClaudeOnlyDocs != [ ]) (
      [ newline ] ++ config.agents.extraClaudeOnlyDocs
    )
  );
  opencodeDocs = pkgs.concatText "opencode-docs.md" (
    [ ./agents-global.md ]
    ++ lib.optionals (config.agents.extraClaudeDocs != [ ]) (
      [ newline ] ++ config.agents.extraClaudeDocs
    )
    ++ lib.optionals (config.agents.extraOpencodeDocs != [ ]) (
      [ newline ] ++ config.agents.extraOpencodeDocs
    )
  );
in
{
  options.agents = {
    extraClaudeDocs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };
    extraOpencodeDocs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };
    extraClaudeOnlyDocs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };
  };

  imports = [
    ./caveman.nix
    ./code-review-graph.nix
    ./rtk.nix
    ./skills.nix
    ./subagents.nix
  ];

  config = {
    home.packages =
      with pkgs;
      lib.lists.flatten [
        (lib.optional isLinux wl-clipboard) # used by agent-shell
        (lib.optional isDarwin pngpaste) # used by agent-shell

        ### Coding agent ###
        claude-agent-acp
        aider-chat-full # another AI thingy
        opencode
        playwright-mcp
        context7-mcp
        mcp-nixos
        github-mcp-server
      ];

    programs.claude-code.enable = true;

    home.file = {
      "${config.home.homeDirectory}/.agents/AGENTS.md".source = combinedDocs;
      "${config.xdg.configHome}/opencode/AGENTS.md".source = opencodeDocs;
      "${config.home.homeDirectory}/.claude/CLAUDE.md".source = claudeDocs;

      "${config.xdg.configHome}/opencode/opencode.json" = {
        text = builtins.toJSON {
          "$schema" = "https://opencode.ai/config.json";
          model = "openrouter/anthropic/claude-sonnet-4.6";
        };
      };

      ".aider.conf.yml".source = (pkgs.formats.yaml { }).generate "aider-conf" {
        cache-prompts = true;
        cache-keepalive-pings = 5;
        code-theme = "monokai";
        auto-commits = false;
        model = "openrouter/anthropic/claude-sonnet-4.6";
        weak-model = "openrouter/anthropic/claude-haiku-4.5";
      };
    };
  };
}
