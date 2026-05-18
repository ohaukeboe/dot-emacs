{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
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
    map
      (name: {
        inherit name;
        path = "${inputs.caveman}/skills/${name}";
      })
      [
        "caveman"
        "caveman-commit"
        "caveman-compress"
        "caveman-help"
        "caveman-review"
        "caveman-stats"
        "cavecrew"
      ]
  );

  cavekitSkills = pkgs.linkFarm "cavekit-skills" (
    map
      (name: {
        inherit name;
        path = "${inputs.cavekit}/skills/${name}";
      })
      [
        "backprop"
        "build"
        # "caveman"
        "check"
        "spec"
      ]
  );

  humanizerSkill = pkgs.linkFarm "humanizer-skill" [
    {
      name = "humanizer";
      path = "${inputs.humanizer-skill}";
    }
  ];

  # descoped/llm-skills — comment out any you don't want
  # domain-finder, github-issues-workflow, code-review, claude-settings,
  # statusline, vite-chunk-split, slack-message, session-snapshot, claude-rules
  llmSkillsSubset = pkgs.linkFarm "llm-skills-subset" (
    map
      (name: {
        inherit name;
        path = "${inputs.llm-skills}/plugins/${name}/skills/${name}";
      })
      [
        "domain-finder"
      ]
  );

  # mattpocock/skills — comment out any you don't want
  # engineering: diagnose, grill-with-docs, improve-codebase-architecture,
  #              prototype, setup-matt-pocock-skills, tdd, to-issues,
  #              to-prd, triage, zoom-out
  # productivity: caveman, grill-me, handoff, write-a-skill
  # misc:         git-guardrails-claude-code, migrate-to-shoehorn,
  #               scaffold-exercises, setup-pre-commit
  # personal:     edit-article, obsidian-vault
  mattpocockSkillsSubset = pkgs.linkFarm "mattpocock-skills-subset" (
    map
      (
        { name, subdir }:
        {
          inherit name;
          path = "${inputs.mattpocock-skills}/skills/${subdir}/${name}";
        }
      )
      [
        # -- engineering --
        {
          name = "diagnose";
          subdir = "engineering";
        }
        {
          name = "grill-with-docs";
          subdir = "engineering";
        }
        {
          name = "improve-codebase-architecture";
          subdir = "engineering";
        }
        {
          name = "prototype";
          subdir = "engineering";
        }
        {
          name = "setup-matt-pocock-skills";
          subdir = "engineering";
        }
        {
          name = "tdd";
          subdir = "engineering";
        }
        {
          name = "to-issues";
          subdir = "engineering";
        }
        {
          name = "to-prd";
          subdir = "engineering";
        }
        {
          name = "triage";
          subdir = "engineering";
        }
        {
          name = "zoom-out";
          subdir = "engineering";
        }

        # -- productivity --
        # { name = "caveman";                         subdir = "productivity"; }
        {
          name = "grill-me";
          subdir = "productivity";
        }
        {
          name = "handoff";
          subdir = "productivity";
        }
        # { name = "write-a-skill";                   subdir = "productivity"; }

        # -- misc --
        # { name = "git-guardrails-claude-code";      subdir = "misc"; }
        # { name = "migrate-to-shoehorn";             subdir = "misc"; }
        # { name = "scaffold-exercises";              subdir = "misc"; }
        # { name = "setup-pre-commit";                subdir = "misc"; }

        # -- personal --
        # { name = "edit-article";                    subdir = "personal"; }
        # { name = "obsidian-vault";                  subdir = "personal"; }
      ]
  );

  mergedSkills = pkgs.symlinkJoin {
    name = "merged-skills";
    paths = [
      ./skills
      "${inputs.emacs-skills}/skills"
      anthropicsSkillsSubset
      cavemanSkillsSubset
      cavekitSkills
      humanizerSkill
      mattpocockSkillsSubset
      llmSkillsSubset
    ];
  };
in
{
  home.file = {
    "${config.home.homeDirectory}/.claude/skills" = {
      source = mergedSkills;
      recursive = true;
    };
    "${config.home.homeDirectory}/.agents/skills" = {
      source = mergedSkills;
      recursive = true;
    };
  };
}
