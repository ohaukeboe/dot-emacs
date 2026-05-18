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
in
{
  home.file = {
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
  };
}
