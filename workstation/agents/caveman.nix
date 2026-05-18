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

  claudeSettings = {
    hooks = {
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = [ { type = "command"; command = "rtk hook claude"; } ];
        }
      ];
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
in
{
  home.packages = [ caveman-shrink ];

  home.file = {
    "${config.home.homeDirectory}/.claude/settings.json" = {
      text = builtins.toJSON claudeSettings;
    };

    "${hooksDir}/package.json".source = "${inputs.caveman}/src/hooks/package.json";
    "${hooksDir}/caveman-config.js".source = "${inputs.caveman}/src/hooks/caveman-config.js";
    "${hooksDir}/caveman-activate.js".source = "${inputs.caveman}/src/hooks/caveman-activate.js";
    "${hooksDir}/caveman-mode-tracker.js".source = "${inputs.caveman}/src/hooks/caveman-mode-tracker.js";
    "${hooksDir}/caveman-stats.js".source = "${inputs.caveman}/src/hooks/caveman-stats.js";
    "${hooksDir}/caveman-statusline.sh".source = "${inputs.caveman}/src/hooks/caveman-statusline.sh";
    "${hooksDir}/caveman-statusline.ps1".source = "${inputs.caveman}/src/hooks/caveman-statusline.ps1";
  };
}
