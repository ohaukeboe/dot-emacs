{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  # Copy a skill directory and inject `disable-model-invocation: true`
  # into its SKILL.md frontmatter (before the closing `---`).
  patchSkill =
    name: src:
    pkgs.runCommand "skill-${name}-no-auto" { } ''
      cp -r ${src} $out
      chmod -R u+w $out
      if ! grep -q '^disable-model-invocation:' $out/SKILL.md; then
        ${pkgs.gnused}/bin/sed -i '0,/^---$/{ /^---$/!b; :a; n; /^---$/!ba; i\
      disable-model-invocation: true
        }' $out/SKILL.md
      fi
    '';

  # Build a linkFarm entry from a record. `repo` and `defaultSubdir` are
  # bound per skill source; the record supplies name + optional overrides.
  mkSkillEntry =
    {
      repo,
      defaultSubdir ? "skills",
    }:
    {
      name,
      disableAuto ? false,
      subdir ? defaultSubdir,
    }:
    let
      src = "${repo}/${subdir}/${name}";
    in
    {
      inherit name;
      path = if disableAuto then patchSkill name src else src;
    };

  anthropicsSkillsSubset = pkgs.linkFarm "anthropics-skills-subset" (
    map (mkSkillEntry { repo = inputs.anthropics-skills; }) [
      { name = "pdf"; }
      {
        name = "skill-creator";
        disableAuto = true;
      }
    ]
  );

  cavemanSkillsSubset = pkgs.linkFarm "caveman-skills-subset" (
    map (mkSkillEntry { repo = inputs.caveman; }) [
      { name = "caveman"; }
      { name = "caveman-commit"; }
      { name = "caveman-compress"; }
      { name = "caveman-help"; }
      { name = "caveman-review"; }
      { name = "caveman-stats"; }
      { name = "cavecrew"; }
    ]
  );

  cavekitSkills = pkgs.linkFarm "cavekit-skills" (
    map (mkSkillEntry { repo = inputs.cavekit; }) [
      { name = "backprop"; }
      { name = "build"; }
      # { name = "caveman"; }
      { name = "check"; }
      { name = "spec"; }
    ]
  );

  humanizerSkill = pkgs.linkFarm "humanizer-skill" [
    {
      name = "humanizer";
      path = patchSkill "humanizer" "${inputs.humanizer-skill}";
    }
  ];

  # descoped/llm-skills — comment out any you don't want
  # domain-finder, github-issues-workflow, code-review, claude-settings,
  # statusline, vite-chunk-split, slack-message, session-snapshot, claude-rules
  #
  # Path layout differs: plugins/<name>/skills/<name>. The mkSkillEntry helper
  # composes `${repo}/${subdir}/${name}`, so set subdir to `plugins/<name>/skills`
  # per entry.
  llmSkillsSubset = pkgs.linkFarm "llm-skills-subset" (
    map (mkSkillEntry { repo = inputs.llm-skills; }) [
      {
        name = "domain-finder";
        subdir = "plugins/domain-finder/skills";
        disableAuto = true;
      }
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
  # mattpocock layout: skills/<subdir>/<name> — pass per-entry `subdir`.
  # Set `disableAuto = true;` on any entry to suppress automatic model
  # invocation (skill only runs on explicit user invocation).
  mattpocockSkillsSubset = pkgs.linkFarm "mattpocock-skills-subset" (
    map (e: mkSkillEntry { repo = inputs.mattpocock-skills; } (e // { subdir = "skills/${e.subdir}"; }))
      [
        # -- engineering --
        # `diagnose` keeps auto-invocation: triggers on bug/test-failure
        # reports — high-signal natural-language trigger.
        {
          name = "diagnose";
          subdir = "engineering";
        }
        {
          name = "grill-with-docs";
          subdir = "engineering";
          disableAuto = true;
        }
        {
          name = "improve-codebase-architecture";
          subdir = "engineering";
          disableAuto = true;
        }
        {
          name = "prototype";
          subdir = "engineering";
          disableAuto = true;
        }
        {
          name = "setup-matt-pocock-skills";
          subdir = "engineering";
          disableAuto = true;
        }
        {
          name = "tdd";
          subdir = "engineering";
          disableAuto = true;
        }
        {
          name = "domain-modeling";
          subdir = "engineering";
        }
        {
          name = "to-issues";
          subdir = "engineering";
          disableAuto = true;
        }
        {
          name = "to-prd";
          subdir = "engineering";
          disableAuto = true;
        }
        {
          name = "triage";
          subdir = "engineering";
          disableAuto = true;
        }

        # -- productivity --
        # { name = "caveman";                         subdir = "productivity"; }
        {
          name = "grill-me";
          subdir = "productivity";
          disableAuto = true;
        }
        {
          name = "handoff";
          subdir = "productivity";
          disableAuto = true;
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

  # Lum1104/Understand-Anything — uncomment skills you want
  # All use plugin layout: understand-anything-plugin/skills/<name>
  understandAnythingSkills = pkgs.linkFarm "understand-anything-skills" (
    map
      (mkSkillEntry {
        repo = inputs.understand-anything;
        defaultSubdir = "understand-anything-plugin/skills";
      })
      [
        { name = "understand"; } # Analyze codebase → interactive knowledge graph
        { name = "understand-chat"; } # Ask questions about a codebase using the knowledge graph
        { name = "understand-dashboard"; } # Launch web dashboard to visualize codebase knowledge graph
        { name = "understand-diff"; } # Analyze git diffs/PRs to understand what changed
        { name = "understand-domain"; } # Extract business domain knowledge → interactive graph
        { name = "understand-explain"; } # Deep-dive explanation of a specific file, function, or module
        { name = "understand-knowledge"; } # Analyze Karpathy-pattern LLM wiki knowledge base
        { name = "understand-onboard"; } # Generate onboarding guide for new team members
      ]
  );

  mergedSkills = pkgs.symlinkJoin {
    name = "merged-skills";
    paths = [
      ./skills
      anthropicsSkillsSubset
      cavemanSkillsSubset
      cavekitSkills
      humanizerSkill
      mattpocockSkillsSubset
      llmSkillsSubset
      understandAnythingSkills
      "${inputs.anthropic-cybersecurity-skills}/skills"
    ]
    ++ config.agents.extraSkillPaths;
  };
in
{
  options.agents.extraSkillPaths = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
  };

  config = {
    # Bypass programs.claude-code.skills / programs.opencode.skills — both
    # upstream modules hardcode `recursive = true` on the resulting home.file
    # entry, which fans ~13k symlinks out on every activation once many
    # skills (e.g. anthropic-cybersecurity-skills) are merged in.
    home.file."${config.home.homeDirectory}/.claude/skills".source = mergedSkills;
    xdg.configFile."opencode/skills".source = mergedSkills;
    home.file."${config.home.homeDirectory}/.agents/skills".source = mergedSkills;
  };
}
