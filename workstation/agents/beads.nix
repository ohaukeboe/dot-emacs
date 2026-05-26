{ pkgs, ... }:
let
  bd = "${pkgs.beads}/bin/bd";

  beadsOpencodeDocs = pkgs.runCommand "beads-opencode-docs.md" { } ''
    ${bd} setup opencode --print > $out
  '';
in
{
  home.packages = [ pkgs.beads ];

  agents.extraOpencodeDocs = [ beadsOpencodeDocs ];

  programs.claude-code.settings.hooks = {
    SessionStart = [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = "${bd} prime";
          }
        ];
      }
    ];
    PreCompact = [
      {
        matcher = "";
        hooks = [
          {
            type = "command";
            command = "${bd} prime";
          }
        ];
      }
    ];
  };
}
