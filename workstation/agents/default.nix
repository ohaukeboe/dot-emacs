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

  # Command prefixes that must never run unprompted. One definition, two
  # consumers: the harness's own ask rules below, and the rewriter chain's
  # guard. The guard exists because a rewriter moves a command's first token
  # off position 0 — `git commit` becomes `rtk git commit` today, and a capped
  # command becomes `agent-process-cap run fg <payload>` — while the docs only
  # say that PreToolUse hooks run before the permission prompt, never whether
  # ask rules are matched against the original input or a hook's updatedInput.
  # Re-asserting them here makes the outcome the same either way.
  sensitivePrefixes = config.agents.sensitiveBashPrefixes;

  # Stages of the single PreToolUse Bash hook, in the order they rewrite.
  rewriterStages = lib.sort (a: b: a.order < b.order) (lib.attrValues config.agents.bashRewriters);

  bashRewriterChain = pkgs.writeShellApplication {
    name = "agent-bash-rewriter-chain";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      stages=(${
        lib.concatMapStringsSep " " (s: lib.escapeShellArg (lib.getExe s.executable)) rewriterStages
      })
      prefixes=(${lib.concatMapStringsSep " " lib.escapeShellArg sensitivePrefixes})

      payload=$(cat)
      tool=$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null || true)
      [ "$tool" = "Bash" ] || exit 0
      original=$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null || true)
      [ -n "$original" ] || exit 0

      # Every failure path keeps the previous command text and carries on: a
      # stage that exits non-zero, prints nothing, or prints something without
      # an updatedInput is treated as "no change". The chain always exits 0,
      # because exit 2 from a PreToolUse hook blocks the call outright.
      current=$payload
      for stage in "''${stages[@]}"; do
        out=$("$stage" <<<"$current" 2>/dev/null) || continue
        [ -n "$out" ] || continue
        updated=$(jq -c '.hookSpecificOutput.updatedInput // empty' <<<"$out" 2>/dev/null) || continue
        [ -n "$updated" ] || continue
        current=$(jq -c --argjson u "$updated" '.tool_input = $u' <<<"$current" 2>/dev/null) || continue
      done

      final=$(jq -r '.tool_input.command // empty' <<<"$current" 2>/dev/null || true)
      [ -n "$final" ] || exit 0

      matched=""
      for prefix in "''${prefixes[@]}"; do
        case "$original" in
          "$prefix"*)
            matched=$prefix
            break
            ;;
        esac
      done

      # Nothing changed and nothing to re-assert: stay silent.
      if [ -z "$matched" ] && [ "$final" = "$original" ]; then
        exit 0
      fi

      input=$(jq -c '.tool_input' <<<"$current")

      if [ -n "$matched" ]; then
        jq -n --argjson input "$input" --arg matched "$matched" \
          '{hookSpecificOutput: {
              hookEventName: "PreToolUse",
              permissionDecision: "ask",
              permissionDecisionReason: ("rewritten command still matches the sensitive prefix \"" + $matched + "\""),
              updatedInput: $input
            }}'
      else
        jq -n --argjson input "$input" \
          '{hookSpecificOutput: {
              hookEventName: "PreToolUse",
              permissionDecisionReason: "rewritten by the bash rewriter chain",
              updatedInput: $input
            }}'
      fi
    '';
  };

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

    bashRewriters = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              order = lib.mkOption {
                type = lib.types.ints.between 0 100;
                description = "Position of the ${name} stage in the chain; lower runs first.";
              };
              executable = lib.mkOption {
                type = lib.types.package;
                description = ''
                  Stage executable. Reads the PreToolUse payload on stdin and prints
                  either nothing (no change) or a hookSpecificOutput carrying
                  updatedInput.
                '';
              };
            };
          }
        )
      );
      default = { };
      description = ''
        Ordered stages of the single PreToolUse hook on the Bash matcher.

        A module that wants to rewrite Bash commands registers a stage here
        rather than adding a PreToolUse hook of its own: Claude Code runs
        matching hooks in parallel and leaves the winning updatedInput
        undefined, so two rewriting hooks would race. See
        docs/adr/0003-agent-bash-rewriter-chain.md.
      '';
    };

    sensitiveBashPrefixes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "git commit"
        "git push"
        "git reset --hard"
        "sudo nixos-rebuild"

        # Destructive filesystem and working-tree commands. Prose in a memory
        # file is a request; an ask rule is enforced by the harness, and still
        # prompts inside a sandboxed auto-allow session.
        "rm -rf"
        "sudo rm"
        "dd"
        "mkfs"
        "git clean"
        "git restore"
        "git checkout --"
      ];
      description = ''
        Bash command prefixes that must always prompt. Rendered into
        programs.claude-code.settings.permissions.ask and re-asserted by the
        rewriter chain on the pre-rewrite command text.
      '';
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
    ./format-on-edit.nix
    ./mcp-servers.nix
    ./memory-cap.nix
    ./process-cap.nix
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

        (collect "packages")
      ];

    programs.claude-code.enable = true;
    programs.claude-code.settings.remoteControlAtStartup = true;
    programs.claude-code.settings.skipAutoPermissionPrompt = true;
    programs.claude-code.settings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    programs.claude-code.settings.skillListingBudgetFraction = 0.02;
    # Give the CLAUDE.md git rule teeth. Prompt text only shapes what the
    # agent tries; an ask rule is enforced by the harness, and still prompts
    # inside a sandboxed auto-allow session. The Bash rules are generated from
    # agents.sensitiveBashPrefixes, which the rewriter chain re-asserts on the
    # pre-rewrite command text.
    programs.claude-code.settings.permissions.ask = map (p: "Bash(${p}:*)") sensitivePrefixes ++ [
      "mcp__plugin_hm_github-mcp__create_or_update_file"
      "mcp__plugin_hm_github-mcp__push_files"
      "mcp__plugin_hm_github-mcp__delete_file"
      "mcp__plugin_hm_github-mcp__merge_pull_request"
      "mcp__plugin_hm_github-mcp__create_pull_request"
    ];
    # Keep the Claude Code sandbox off. Its bubblewrap/seccomp jail broke nix
    # daemon access, ssh-agent signing and nested sessions more often than it
    # helped.
    programs.claude-code.settings.sandbox.enabled = false;
    # Absorbed from former security-guidance.nix:
    programs.claude-code.settings.enabledPlugins = {
      "security-guidance@claude-plugins-official" = true;
      "claude-security@claude-plugins-official" = true;
      "frontend-design@claude-plugins-official" = false;
      "code-simplifier@claude-plugins-official" = true;
      "claude-md-management@claude-plugins-official" = true;
    };

    programs.claude-code.settings.hooks = lib.zipAttrsWith (_: lib.concatLists) (
      (map (t: t.hooks) toolValues)
      # One hook for the whole rewriter chain. Matching hooks run in parallel
      # and the winning updatedInput is undefined, so a second rewriting hook
      # on the Bash matcher would race this one.
      ++ lib.optional (rewriterStages != [ ]) {
        PreToolUse = [
          {
            matcher = "Bash";
            hooks = [
              {
                type = "command";
                command = lib.getExe bashRewriterChain;
              }
            ];
          }
        ];
      }
    );

    assertions =
      let
        orders = map (s: s.order) rewriterStages;
      in
      [
        {
          assertion = sensitivePrefixes != [ ] || config.agents.bashRewriters == { };
          message = ''
            agents.sensitiveBashPrefixes is empty while Bash rewriters are registered. A
            rewriter moves a command's first token off position 0, so an empty list silently
            disables the only guard that keeps the ask rules meaningful. Restore the list in
            workstation/agents/default.nix.
          '';
        }
        {
          assertion = lib.length (lib.unique orders) == lib.length orders;
          message = ''
            Two agents.bashRewriters stages share an order (${lib.concatMapStringsSep ", " toString orders}).
            Equal orders reintroduce exactly the nondeterminism the chain exists to remove; give
            each stage its own order in the module that declares it.
          '';
        }
        {
          assertion =
            !(config.agents.bashRewriters ? processCap)
            || config.agents.bashRewriters.processCap.order == lib.foldl' lib.max 0 orders;
          message = ''
            The processCap stage is not the last agents.bashRewriters stage. It consumes the
            final command text, so a stage after it would rewrite text that is already inside
            the base64 payload. Lower the other stage's order, or raise
            agents.bashRewriters.processCap.order in workstation/agents/process-cap.nix.
          '';
        }
      ];
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
