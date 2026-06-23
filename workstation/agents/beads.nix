{ pkgs, config, ... }:
let
  bd = "${pkgs.beads}/bin/bd";

  beadsOpencodeDocs = pkgs.runCommand "beads-opencode-docs.md" { } ''
    ${bd} setup opencode --print > $out
  '';
in
{
  # Claude Code gets beads via the upstream plugin (vendored release tree, which
  # doubles as a marketplace). The plugin ships its own SessionStart/PreCompact
  # `bd prime` hooks plus skills + slash commands, so we no longer hand-roll them.
  # The `bd` CLI the plugin's hooks invoke still comes from pkgs.beads on PATH.
  programs.claude-code.marketplaces.beads-marketplace = pkgs.nvSources.beads.src;
  programs.claude-code.settings.enabledPlugins."beads@beads-marketplace" = true;
  # Prevent stale .backup files from blocking future switches
  home.file."${config.home.homeDirectory}/.claude/plugins/known_marketplaces.json".force = true;

  agents.tools.beads = {
    packages = [ pkgs.beads ];
    # Opencode has no plugin system; keep the generated setup doc for it.
    docs.opencodeOnly = [ beadsOpencodeDocs ];
  };
}
