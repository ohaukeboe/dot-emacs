{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

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
    ./auto-mode.nix
    ./beads.nix
    ./caveman.nix
    ./code-review-graph.nix
    ./mcp-servers.nix
    ./rtk.nix
    ./skills.nix
    ./spec-kit.nix
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

        # Claude Code sandbox runtime: bubblewrap builds the namespace jail,
        # socat proxies the network access allowed through it.
        (lib.optional isLinux bubblewrap)
        socat

        (collect "packages")
      ];

    programs.claude-code.enable = true;
    programs.claude-code.settings.remoteControlAtStartup = true;
    programs.claude-code.settings.skipAutoPermissionPrompt = true;
    programs.claude-code.settings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    # Pin the executor shell to a store-backed bash. The sandbox resolves its
    # shell with Node's fs.statSync, and statx(2) on the envfs-provided
    # /bin/bash returns ENOENT, which aborted every sandboxed Bash call with
    # "Shell '/bin/bash' not found in PATH". See services.envfs in
    # common/system/system.nix for the other half of the fix.
    programs.claude-code.settings.env.CLAUDE_CODE_SHELL = "${pkgs.bash}/bin/bash";
    programs.claude-code.settings.skillListingBudgetFraction = 0.02;
    # Give the CLAUDE.md git rule teeth. Prompt text only shapes what the
    # agent tries; an ask rule is enforced by the harness, and still prompts
    # inside a sandboxed auto-allow session.
    programs.claude-code.settings.permissions.ask = [
      "Bash(git commit:*)"
      "Bash(git push:*)"
      "Bash(git reset --hard:*)"
      "Bash(sudo nixos-rebuild:*)"

      "mcp__plugin_hm_github-mcp__create_or_update_file"
      "mcp__plugin_hm_github-mcp__push_files"
      "mcp__plugin_hm_github-mcp__delete_file"
      "mcp__plugin_hm_github-mcp__merge_pull_request"
      "mcp__plugin_hm_github-mcp__create_pull_request"
    ];
    # Run tool calls inside the sandbox, and refuse to fall back to an
    # unsandboxed run if it cannot be set up.
    programs.claude-code.settings.sandbox = {
      enabled = true;
      failIfUnavailable = true;
      # The default seccomp filter rejects socket(AF_UNIX, ...) outright, so
      # the nix client cannot reach /nix/var/nix/daemon-socket/socket and every
      # build, eval or flake fetch dies with "cannot create Unix domain socket:
      # Operation not permitted". On Linux allowUnixSockets (a path list) is
      # ignored -- seccomp cannot filter by path -- so the all-or-nothing knob
      # is the only one that works. Same block breaks ssh-agent, so signed
      # commits fail with "Error connecting to agent: Operation not permitted"
      # (gpg.format = ssh, commit.gpgsign = true), and it stops a nested Claude
      # Code session binding its own sandbox mux socket.
      network.allowAllUnixSockets = true;
      filesystem.allowWrite = [
        # nix keeps its fetcher/eval SQLite caches here; without write access
        # every command fails on "unable to open database file".
        "${config.home.homeDirectory}/.cache/nix"
        "${config.home.homeDirectory}/.local/state/nix"
      ];
    };
    # Absorbed from former security-guidance.nix:
    programs.claude-code.settings.enabledPlugins = {
      "security-guidance@claude-plugins-official" = true;
      "claude-security@claude-plugins-official" = true;
      "frontend-design@claude-plugins-official" = false;
      "code-simplifier@claude-plugins-official" = true;
      "claude-md-management@claude-plugins-official" = true;
    };

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
