{ pkgs, config, ... }:
let
  bd = "${pkgs.beads}/bin/bd";

  beadsOpencodeDocs = pkgs.runCommand "beads-opencode-docs.md" { } ''
    ${bd} setup opencode --print > $out
  '';

  # The vendored marketplace with every beads slash command made user-only, so
  # the ~29 `beads:*` descriptions leave the model's skill listing. Commands are
  # patched with the `patchSkill` sed from skills.nix; `prime.md` and
  # `template.md` have no frontmatter, so they get a minimal one. The version
  # suffix makes Claude Code re-copy the plugin into its cache, which it skips
  # when the version is unchanged. The `beads:beads` skill is left as is.
  beadsMarketplace = pkgs.runCommand "beads-marketplace-no-auto" { } ''
    cp -r ${pkgs.nvSources.beads.src} $out
    chmod -R u+w $out
    cmds=$out/plugins/beads/skills/beads/commands
    for f in $cmds/*.md; do
      if grep -q '^disable-model-invocation:' "$f"; then
        continue
      elif [ "$(head -n 1 "$f")" = "---" ]; then
        ${pkgs.gnused}/bin/sed -i '0,/^---$/{ /^---$/!b; :a; n; /^---$/!ba; i\
    disable-model-invocation: true
        }' "$f"
      else
        { printf -- '---\ndisable-model-invocation: true\n---\n'; cat "$f"; } > "$f.tmp"
        mv "$f.tmp" "$f"
      fi
    done

    # Every command must now carry the key inside a closed frontmatter block.
    # stdenv sets nullglob, so a moved commands dir would otherwise pass empty.
    files=($cmds/*.md)
    if [ ''${#files[@]} -eq 0 ]; then
      echo "workstation/agents/beads.nix: no commands under $cmds. Upstream moved them;" \
        "point cmds in beadsMarketplace at the new directory." >&2
      exit 1
    fi
    for f in "''${files[@]}"; do
      awk 'NR == 1 { if ($0 != "---") exit; next }
           $0 == "---" { closed = 1; exit }
           /^disable-model-invocation: true$/ { found = 1 }
           END { exit !(found && closed) }' "$f" || {
        echo "workstation/agents/beads.nix: $f has no disable-model-invocation: true" \
          "in its frontmatter. Fix the patch loop in beadsMarketplace for this file's layout." >&2
        exit 1
      }
    done

    # Keep the two version fields in step.
    suffixVersion() {
      ${pkgs.jq}/bin/jq "$2 += \"+hm1\"" "$out/$1" > "$out/$1.tmp"
      mv "$out/$1.tmp" "$out/$1"
    }
    suffixVersion plugins/beads/.claude-plugin/plugin.json '.version'
    suffixVersion .claude-plugin/marketplace.json '.plugins[0].version'
  '';
in
{
  # Claude Code gets beads via the upstream plugin (vendored release tree, which
  # doubles as a marketplace). The plugin ships its own SessionStart/PreCompact
  # `bd prime` hooks plus skills + slash commands, so we no longer hand-roll them.
  # The `bd` CLI the plugin's hooks invoke still comes from pkgs.beads on PATH.
  programs.claude-code.marketplaces.beads-marketplace = beadsMarketplace;
  programs.claude-code.settings.enabledPlugins."beads@beads-marketplace" = true;
  # beads is the task tracker. On Opus 5.x these tools are not offered anyway.
  # The deny also turns off the agent-teams shared task list, which is accepted
  # (spec 007 Assumptions). TaskStop, TaskOutput and SendMessage stay allowed.
  programs.claude-code.settings.permissions.deny = [
    "TodoWrite"
    "TaskCreate"
    "TaskGet"
    "TaskList"
    "TaskUpdate"
  ];
  # Prevent stale .backup files from blocking future switches
  home.file."${config.home.homeDirectory}/.claude/plugins/known_marketplaces.json".force = true;

  agents.tools.beads = {
    packages = [ pkgs.beads ];
    # Opencode has no plugin system; keep the generated setup doc for it.
    docs.opencodeOnly = [ beadsOpencodeDocs ];
  };
}
