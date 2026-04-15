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
  anthropicsSkillsSubset = pkgs.linkFarm "anthropics-skills-subset" [
    {
      name = "pdf";
      path = "${inputs.anthropics-skills}/skills/pdf";
    }
    {
      name = "skill-creator";
      path = "${inputs.anthropics-skills}/skills/skill-creator";
    }
  ];

  mergedSkills = pkgs.symlinkJoin {
    name = "merged-skills";
    paths = [
      ./skills
      "${inputs.emacs-skills}/skills"
      anthropicsSkillsSubset
    ];
  };
in
{
  home.packages = with pkgs; lib.lists.flatten [
    (lib.optional isLinux wl-clipboard-x11) # used by agent-shell
    (lib.optional isDarwin pngpaste) # used by agent-shell

    ### Coding agent ###
    claude-code
    claude-agent-acp
    aider-chat-full # another AI thingy
    opencode
    playwright-mcp
    rtk # CLI proxy for minimizing token use
  ];

  home.file = {
    "${config.home.homeDirectory}/.agents/AGENTS.md".source = ./agents-global.md;
    "${config.xdg.configHome}/opencode/AGENTS.md".source = ./agents-global.md;
    "${config.home.homeDirectory}/.claude/CLAUDE.md".source = ./agents-global.md;

    "${config.home.homeDirectory}/.claude/settings.json".source = ./claude-settings.json;

    "${config.home.homeDirectory}/.claude/skills" = {
      source = mergedSkills;
      recursive = true;
    };
    "${config.home.homeDirectory}/.claude/skills/humanizer/SKILL.md".source =
      "${inputs.humanizer-skill}/SKILL.md";
    "${config.home.homeDirectory}/.agents/skills" = {
      source = mergedSkills;
      recursive = true;
    };
    "${config.home.homeDirectory}/.agents/skills/humanizer/SKILL.md".source =
      "${inputs.humanizer-skill}/SKILL.md";

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

  home.activation = {
    rtkHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init -g --hook-only
      $DRY_RUN_CMD ${pkgs.rtk}/bin/rtk init -g --opencode --hook-only
    '';
  };
}
