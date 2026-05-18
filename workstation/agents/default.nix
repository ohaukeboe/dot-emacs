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

  cavemanSkillsSubset = pkgs.linkFarm "caveman-skills-subset" (
    map (name: { inherit name; path = "${inputs.caveman}/skills/${name}"; }) [
      "caveman"
      "caveman-commit"
      "caveman-compress"
      "caveman-help"
      "caveman-review"
      "caveman-stats"
      "cavecrew"
    ]
  );

  mergedSkills = pkgs.symlinkJoin {
    name = "merged-skills";
    paths = [
      ./skills
      "${inputs.emacs-skills}/skills"
      anthropicsSkillsSubset
      cavemanSkillsSubset
    ];
  };

  caveman-shrink = pkgs.buildNpmPackage {
    pname = "caveman-shrink";
    version = "0.1.0";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/caveman-shrink/-/caveman-shrink-0.1.0.tgz";
      hash = "sha256-K0DszONf6M4UXmwC/gLRkiNatlXLNhQkTKmBiMBPh6c=";
    };
    sourceRoot = "package";
    forceEmptyCache = true;
    npmDepsHash = "sha256-Rx3AlLPKduQJ1ZRh7BKe3O5HX896BAJm+hLgi5tuh+k=";
    dontNpmBuild = true;
    preInstall = "mkdir -p node_modules";
    postPatch = ''
      cat > package-lock.json << 'LOCKEOF'
{
  "name": "caveman-shrink",
  "version": "0.1.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "caveman-shrink",
      "version": "0.1.0"
    }
  }
}
LOCKEOF
    '';
  };

  cavemanHooksDir = "${config.home.homeDirectory}/.claude/hooks";

  claudeSettings = {
    hooks = {
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = [ { type = "command"; command = "rtk hook claude"; } ];
        }
      ];
      SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = ''${pkgs.nodejs}/bin/node "${cavemanHooksDir}/caveman-activate.js"'';
              timeout = 5;
              statusMessage = "Loading caveman mode...";
            }
          ];
        }
      ];
      UserPromptSubmit = [
        {
          hooks = [
            {
              type = "command";
              command = ''${pkgs.nodejs}/bin/node "${cavemanHooksDir}/caveman-mode-tracker.js"'';
              timeout = 5;
              statusMessage = "Tracking caveman mode...";
            }
          ];
        }
      ];
    };
    statusLine = {
      type = "command";
      command = ''bash "${cavemanHooksDir}/caveman-statusline.sh"'';
    };
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
    context7-mcp
    caveman-shrink
  ];

  home.file = {
    "${config.home.homeDirectory}/.agents/AGENTS.md".source = ./agents-global.md;
    "${config.xdg.configHome}/opencode/AGENTS.md".source = ./agents-global.md;
    "${config.home.homeDirectory}/.claude/CLAUDE.md".source = ./agents-global.md;

    "${config.home.homeDirectory}/.claude/settings.json" = {
      text = builtins.toJSON claudeSettings;
    };

    "${cavemanHooksDir}/package.json".source = "${inputs.caveman}/src/hooks/package.json";
    "${cavemanHooksDir}/caveman-config.js".source = "${inputs.caveman}/src/hooks/caveman-config.js";
    "${cavemanHooksDir}/caveman-activate.js".source = "${inputs.caveman}/src/hooks/caveman-activate.js";
    "${cavemanHooksDir}/caveman-mode-tracker.js".source = "${inputs.caveman}/src/hooks/caveman-mode-tracker.js";
    "${cavemanHooksDir}/caveman-stats.js".source = "${inputs.caveman}/src/hooks/caveman-stats.js";
    "${cavemanHooksDir}/caveman-statusline.sh".source = "${inputs.caveman}/src/hooks/caveman-statusline.sh";
    "${cavemanHooksDir}/caveman-statusline.ps1".source = "${inputs.caveman}/src/hooks/caveman-statusline.ps1";

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
