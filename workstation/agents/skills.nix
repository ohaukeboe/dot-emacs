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

  # mattpocock/skills — install ALL skills, enumerated dynamically from the
  # repo so new upstream skills appear automatically on input bump. Layout:
  # skills/<category>/<name>. Categories below are scanned; `deprecated` is
  # intentionally skipped (upstream-retired skills).
  #
  # Every skill defaults to explicit-invocation only (disableAuto). Skills in
  # `mattpocockAutoInvoke` keep automatic model invocation.
  mattpocockAutoInvoke = [
    "codebase-design" # module design vocabulary
    "code-review" # branch/PR/diff review
    "diagnosing-bugs" # bug/failure reports
    "resolving-merge-conflicts" # merge/rebase conflicts
  ];
  mattpocockCategories = [
    "engineering"
    "in-progress"
    "misc"
    "productivity"
  ];
  mattpocockSkills = pkgs.linkFarm "mattpocock-skills" (
    lib.concatMap (
      category:
      let
        dir = "${inputs.mattpocock-skills}/skills/${category}";
        names = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir));
      in
      map (
        name:
        mkSkillEntry { repo = inputs.mattpocock-skills; } {
          inherit name;
          subdir = "skills/${category}";
          disableAuto = !(builtins.elem name mattpocockAutoInvoke);
        }
      ) names
    ) mattpocockCategories
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
      mattpocockSkills
      llmSkillsSubset
      understandAnythingSkills
      "${inputs.anthropic-cybersecurity-skills}/skills"
      # privacy-data-protection-skills — 282 skills via privacy-skills-complete
      # plugin (superset of all 20 individual plugins in the repo).
      # All are auto-invoked; set CLAUDE_SKILL_FILTER to limit if needed.
      "${inputs.privacy-data-protection-skills}/plugins/privacy-skills-complete/skills"
    ]
    ++ config.agents.extraSkillPaths;
  };
in
{
  options.agents.extraSkillPaths = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
  };

  config =
    let
      # The programs.claude-code module (personal-plugin support, claude-code
      # ≥ 2.1.157) installs its generated MCP/LSP plugin as a *child* home.file
      # at `.claude/skills/claude-code-home-manager`. That child cannot coexist
      # with our single dir-symlink at `.claude/skills` (home-manager aborts with
      # "installing file ... outside $HOME"), and making the parent `recursive`
      # would fan ~thousands of per-file symlinks out on every activation — the
      # very thing this monolithic symlink exists to avoid.
      #
      # Instead: fold the module's generated plugin into the merged store dir so
      # a single symlink still serves everything, then suppress the module's
      # separate child entry. MCP/LSP registration keeps working because the
      # plugin lands at the same path claude-code expects.
      ccPluginKey = "${config.home.homeDirectory}/.claude/skills/claude-code-home-manager";
      ccPluginSource = config.home.file.${ccPluginKey}.source;
      skillsWithPlugin = pkgs.symlinkJoin {
        name = "claude-skills-with-plugin";
        paths = [
          mergedSkills
          (pkgs.linkFarm "claude-code-hm-plugin-skill" [
            {
              name = "claude-code-home-manager";
              path = ccPluginSource;
            }
          ])
        ];
      };
    in
    {
      home.file.${ccPluginKey}.enable = lib.mkForce false;
      home.file."${config.home.homeDirectory}/.claude/skills".source = skillsWithPlugin;
      xdg.configFile."opencode/skills".source = mergedSkills;
      home.file."${config.home.homeDirectory}/.agents/skills".source = mergedSkills;
    };
}
