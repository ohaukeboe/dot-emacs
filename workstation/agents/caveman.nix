{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
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

  hooksDir = "${config.home.homeDirectory}/.claude/hooks";
in
{
  home.packages = [ caveman-shrink ];

  agents.extraOpencodeDocs = [ "${inputs.caveman}/src/rules/caveman-activate.md" ];

  programs.claude-code.hooksDir = "${inputs.caveman}/src/hooks";

  programs.claude-code.settings = {
    hooks = {
      SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = ''${pkgs.nodejs}/bin/node "${hooksDir}/caveman-activate.js"'';
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
              command = ''${pkgs.nodejs}/bin/node "${hooksDir}/caveman-mode-tracker.js"'';
              timeout = 5;
              statusMessage = "Tracking caveman mode...";
            }
          ];
        }
      ];
    };
    statusLine = {
      type = "command";
      command = ''bash "${hooksDir}/caveman-statusline.sh"'';
    };
  };
}
