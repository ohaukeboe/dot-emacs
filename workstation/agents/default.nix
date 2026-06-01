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

  joinDocs = paths: lib.concatStringsSep "\n" (map (p: builtins.readFile p) paths);

  active = lib.filterAttrs (_: t: t.enable) config.agents.tools;
  toolValues = lib.attrValues active;
  collect = field: lib.concatLists (map (t: t.${field}) toolValues);
  collectDocs = sub: lib.concatLists (map (t: t.docs.${sub}) toolValues);

  toolSubmodule =
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to enable the ${name} agent tool integration.";
        };
        packages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Packages contributed to home.packages.";
        };
        mcpServers = lib.mkOption {
          type = lib.types.attrsOf lib.types.attrs;
          default = { };
          description = "MCP servers contributed to programs.mcp.servers.";
        };
        hooks = lib.mkOption {
          type = lib.types.attrsOf (lib.types.listOf lib.types.attrs);
          default = { };
          description = "Claude Code hook entries by phase. Lists from different tools are concatenated per phase.";
        };
        docs = {
          both = lib.mkOption {
            type = lib.types.listOf lib.types.path;
            default = [ ];
            description = "Docs included in both Claude and Opencode contexts.";
          };
          claudeOnly = lib.mkOption {
            type = lib.types.listOf lib.types.path;
            default = [ ];
            description = "Docs included only in Claude Code context.";
          };
          opencodeOnly = lib.mkOption {
            type = lib.types.listOf lib.types.path;
            default = [ ];
            description = "Docs included only in Opencode context.";
          };
        };
        skills = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Skill directories contributed to agents.extraSkillPaths.";
        };
      };
    };
in
{
  options.agents = {
    tools = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule toolSubmodule);
      default = { };
      description = "Per-tool agent integrations (caveman, rtk, beads, code-review-graph, ...).";
    };

    docs = {
      both = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "Top-level docs added to both Claude and Opencode (merged with per-tool docs).";
      };
      claudeOnly = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "Top-level docs added only to Claude Code context.";
      };
      opencodeOnly = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "Top-level docs added only to Opencode context.";
      };
    };
  };

  imports = [
    ./beads.nix
    ./caveman.nix
    ./code-review-graph.nix
    ./mcp-servers.nix
    ./rtk.nix
    ./skills.nix
  ];

  config = {
    # Fold active tools into the global options.
    agents.docs.both = collectDocs "both";
    agents.docs.claudeOnly = collectDocs "claudeOnly";
    agents.docs.opencodeOnly = collectDocs "opencodeOnly";

    agents.extraSkillPaths = collect "skills";

    home.packages =
      with pkgs;
      lib.lists.flatten [
        (lib.optional isLinux wl-clipboard) # used by agent-shell
        (lib.optional isDarwin pngpaste) # used by agent-shell

        ### Coding agent ###
        claude-agent-acp
        aider-chat-full # another AI thingy

        ### Agent Tools ###
        chrome-devtools-mcp
        mcp-nixos
        github-mcp-server

        (collect "packages")
      ];

    programs.claude-code.enable = true;
    programs.claude-code.settings.remoteControlAtStartup = true;
    programs.claude-code.settings.skipAutoPermissionPrompt = true;
    programs.claude-code.settings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    programs.claude-code.settings.skillListingBudgetFraction = 0.02;
    # Absorbed from former security-guidance.nix:
    programs.claude-code.settings.enabledPlugins."security-guidance@claude-plugins-official" = true;
    programs.claude-code.settings.hooks = lib.zipAttrsWith (_: lib.concatLists) (
      map (t: t.hooks) toolValues
    );
    programs.claude-code.context = joinDocs (
      [ ./agents-global.md ] ++ config.agents.docs.both ++ config.agents.docs.claudeOnly
    );

    programs.mcp.servers = lib.foldl' (acc: t: acc // t.mcpServers) { } toolValues;

    programs.opencode.enable = true;
    programs.opencode.settings = {
      model = "openrouter/anthropic/claude-sonnet-4.6";
    };
    programs.opencode.context = joinDocs (
      [ ./agents-global.md ] ++ config.agents.docs.both ++ config.agents.docs.opencodeOnly
    );

    home.file = {
      "${config.home.homeDirectory}/.agents/AGENTS.md".text = joinDocs (
        [ ./agents-global.md ] ++ config.agents.docs.both
      );

      ".aider.conf.yml".source = (pkgs.formats.yaml { }).generate "aider-conf" {
        cache-prompts = true;
        cache-keepalive-pings = 5;
        code-theme = "monokai";
        auto-commits = false;
        model = "openrouter/anthropic/claude-sonnet-4.6";
        weak-model = "openrouter/anthropic/claude-haiku-4.5";
      };
    };

    # Absorbed from former subagents.nix:
    agents.tools.subagents = {
      docs.claudeOnly = [ ./subagents-docs.md ];
    };
  };
}
