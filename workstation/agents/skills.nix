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
  # `listing` is not used here: `listingOverrides` reads it off the records.
  mkSkillEntry =
    {
      repo,
      defaultSubdir ? "skills",
    }:
    {
      name,
      disableAuto ? false,
      subdir ? defaultSubdir,
      listing ? null,
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
    ]
  );

  # `name-only` keeps these out of the listing's descriptions but leaves them
  # model-invocable: `build/SKILL.md` calls `backprop` and `spec` through the
  # Skill tool, the same callee rule as the mattpocock skills below.
  cavekitRecords = [
    {
      name = "backprop";
      listing = "name-only";
    }
    {
      name = "build";
      listing = "name-only";
    }
    # { name = "caveman"; }
    {
      name = "check";
      listing = "name-only";
    }
    {
      name = "spec";
      listing = "name-only";
    }
  ];
  cavekitSkills = pkgs.linkFarm "cavekit-skills" (
    map (mkSkillEntry { repo = inputs.cavekit; }) cavekitRecords
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
  # Every skill defaults to explicit-invocation only (disableAuto), with two
  # exceptions that stay model-invocable:
  #
  #   1. `mattpocockAutoInvoke` — skills we want the model to reach for on its
  #      own, without the user typing a slash command.
  #   2. Skills that other mattpocock skills *call* via the Skill tool. These
  #      are composed, not entered directly: `/grill-with-docs` is a two-line
  #      body that tells the model to call "grilling" and "domain-modeling".
  #      Marking a callee `disable-model-invocation: true` breaks every caller,
  #      so callees are detected below and left auto-invocable.
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

  # [{ name, subdir, body }] for every skill in the scanned categories.
  mattpocockAll = lib.concatMap (
    category:
    let
      subdir = "skills/${category}";
      dir = "${inputs.mattpocock-skills}/${subdir}";
      names = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir));
    in
    map (name: {
      inherit name subdir;
      body = builtins.readFile "${dir}/${name}/SKILL.md";
    }) names
  ) mattpocockCategories;

  # A skill is a "callee" if some *other* skill's body names it in quotes, the
  # form every `call the Skill tool with "x"` instruction upstream uses.
  mattpocockCallees = builtins.filter (
    name:
    builtins.any (other: other.name != name && lib.hasInfix ''"${name}"'' other.body) mattpocockAll
  ) (map (s: s.name) mattpocockAll);

  # Skills installed under another name, because a built-in Claude Code skill
  # has the upstream one. A personal skill shadows the built-in of the same
  # name, and the walkthrough skill calls the built-in `code-review` through
  # the Skill tool, which only answers to the unshadowed name.
  mattpocockRenames = {
    "code-review" = "code-review-axes";
  };

  # A skill whose SKILL.md names a renamed skill, in its frontmatter or in a
  # "call the Skill tool with" instruction, gets the new name written in, so
  # `implement` still reaches the two-axis review rather than the built-in.
  renameSkillRefs =
    name: src:
    pkgs.runCommand "skill-${name}-renamed" { } ''
      cp -r ${src} $out
      chmod -R u+w $out
      ${lib.concatStrings (
        lib.mapAttrsToList (from: to: ''
          ${pkgs.gnused}/bin/sed -i -E 's/${from}([^-a-z]|$)/${to}\1/g' $out/SKILL.md
        '') mattpocockRenames
      )}
    '';

  mattpocockSkills = pkgs.linkFarm "mattpocock-skills" (
    map (
      {
        name,
        subdir,
        body,
      }:
      let
        newName = mattpocockRenames.${name} or name;
        src = "${inputs.mattpocock-skills}/${subdir}/${name}";
        renamed =
          if builtins.any (from: lib.hasInfix from body) (builtins.attrNames mattpocockRenames) then
            renameSkillRefs name src
          else
            src;
      in
      {
        name = newName;
        path =
          if builtins.elem name (mattpocockAutoInvoke ++ mattpocockCallees) then
            renamed
          else
            patchSkill newName renamed;
      }
    ) mattpocockAll
  );

  # Lum1104/Understand-Anything — uncomment skills you want
  # All use plugin layout: understand-anything-plugin/skills/<name>
  # Domain skills, entered by slash command only, so they stay out of the
  # automatic listing (`user-invocable-only`).
  understandRecords = map (r: r // { listing = "user-invocable-only"; }) [
    { name = "understand"; } # Analyze codebase → interactive knowledge graph
    { name = "understand-chat"; } # Ask questions about a codebase using the knowledge graph
    { name = "understand-dashboard"; } # Launch web dashboard to visualize codebase knowledge graph
    { name = "understand-diff"; } # Analyze git diffs/PRs to understand what changed
    { name = "understand-domain"; } # Extract business domain knowledge → interactive graph
    { name = "understand-explain"; } # Deep-dive explanation of a specific file, function, or module
    { name = "understand-knowledge"; } # Analyze Karpathy-pattern LLM wiki knowledge base
    { name = "understand-onboard"; } # Generate onboarding guide for new team members
  ];
  understandAnythingSkills = pkgs.linkFarm "understand-anything-skills" (
    map (mkSkillEntry {
      repo = inputs.understand-anything;
      defaultSubdir = "understand-anything-plugin/skills";
    }) understandRecords
  );

  # skillOverrides entries from the records' `listing` field: the runtime
  # filter that keeps a skill installed but out of the automatic listing.
  listingOverrides = lib.listToAttrs (
    map (r: lib.nameValuePair r.name r.listing) (
      builtins.filter (r: (r.listing or null) != null) (cavekitRecords ++ understandRecords)
    )
  );

  # trailofbits/skills — plugin layout: plugins/<name>/skills/<name>.
  # The repo ships ~44 plugins; add entries as needed.
  trailofbitsSkills = pkgs.linkFarm "trailofbits-skills" (
    map (mkSkillEntry { repo = inputs.trailofbits-skills; }) [
      # Interactive HTML walkthrough for reviewing code changes.
      # Upstream SKILL.md already sets disable-model-invocation.
      {
        name = "review-walkthrough";
        subdir = "plugins/review-walkthrough/skills";
      }
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
      trailofbitsSkills
      # Bulk skill packs disabled: together ~1101 skills, all model-invocable,
      # none relevant to this NixOS/Emacs workflow. They blow the skill-listing
      # budget (the harness default skillListingBudgetFraction 0.01 → listing
      # truncated, skills_truncated), hiding the curated dev skills above.
      # Re-enable a line to bring a pack back, and give its skills
      # `agents.skillOverrides` entries (the runtime filter) so they stay out
      # of the listing.
      #
      # anthropic-cybersecurity-skills — 818 skills (offensive-sec / DFIR).
      # "${inputs.anthropic-cybersecurity-skills}/skills"
      #
      # privacy-data-protection-skills — 282 skills via privacy-skills-complete
      # plugin (superset of all 20 individual plugins in the repo).
      # "${inputs.privacy-data-protection-skills}/plugins/privacy-skills-complete/skills"
    ]
    ++ config.agents.extraSkillPaths;
  };
in
{
  options.agents.extraSkillPaths = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
  };

  # Written to Claude Code's `skillOverrides`. Applies to user skills only,
  # not plugin skills. Hosts add entries for the skills they install.
  options.agents.skillOverrides = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.enum [
        "on"
        "name-only"
        "user-invocable-only"
        "off"
      ]
    );
    default = { };
    description = "Per-skill listing in Claude Code: skill name to `skillOverrides` value.";
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
          # Claude-only skills, kept out of `mergedSkills`: opencode and
          # ~/.agents/skills readers may not honour `disable-model-invocation`,
          # and /bead-handoff must never run on its own.
          ./skills-claude-only
          # Opt-in MCP servers as skills-dir plugins (hm-mobile, hm-browser),
          # off by default; mcp-servers.nix builds them. Their names must not
          # clash with any skill name.
          (pkgs.linkFarm "claude-opt-in-plugins" config.agents.claudeSkillsDirPlugins)
        ];
      };
    in
    {
      agents.skillOverrides = listingOverrides;
      programs.claude-code.settings.skillOverrides = config.agents.skillOverrides;
      home.file.${ccPluginKey}.enable = lib.mkForce false;
      home.file."${config.home.homeDirectory}/.claude/skills".source = skillsWithPlugin;
      xdg.configFile."opencode/skills".source = mergedSkills;
      home.file."${config.home.homeDirectory}/.agents/skills".source = mergedSkills;
    };
}
