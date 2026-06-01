{ pkgs, ... }:
let
  bd = "${pkgs.beads}/bin/bd";

  beadsOpencodeDocs = pkgs.runCommand "beads-opencode-docs.md" { } ''
    ${bd} setup opencode --print > $out
  '';
in
{
  agents.tools.beads = {
    packages = [ pkgs.beads ];
    docs.opencodeOnly = [ beadsOpencodeDocs ];
    hooks = {
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
  };
}
