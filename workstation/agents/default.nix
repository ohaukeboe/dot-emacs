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
  chrome-devtools-mcp = pkgs.buildNpmPackage {
    pname = "chrome-devtools-mcp";
    version = "1.0.1";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-1.0.1.tgz";
      hash = "sha256-8CyjSlq3caR9BbfmKJsAfSjVcMsNdwIlTeRctEaDra8=";
    };
    sourceRoot = "package";
    npmDepsFetcherVersion = 2;
    npmDepsHash = "sha256-v6ZX9uqsEtYwiDRLa95SieDu+5fzuZcJEHeNhoCmNSo=";
    npmFlags = [
      "--omit=dev"
      "--ignore-scripts"
    ];
    dontNpmBuild = true;
    preInstall = "mkdir -p node_modules";
    postPatch = "cp ${./chrome-devtools-mcp-lock.json} package-lock.json";
  };
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
    ./beads.nix
    ./caveman.nix
    # ./code-review-graph.nix
    ./mcp-servers.nix
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

        ### Agent Tools ###
        chrome-devtools-mcp
        mcp-nixos
        github-mcp-server
      ];

    programs.claude-code.enable = true;
    programs.claude-code.settings.remoteControlAtStartup = true;
    programs.claude-code.settings.skipAutoPermissionPrompt = true;
    programs.claude-code.settings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    programs.claude-code.settings.skillListingBudgetFraction = 0.02;

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
