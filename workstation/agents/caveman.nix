{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.agents.tools.caveman;

  caveman-shrink = pkgs.buildNpmPackage {
    pname = "caveman-shrink";
    version = pkgs.nvSources.caveman-shrink.version;
    src = pkgs.nvSources.caveman-shrink.src;
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

  # Path the upstream hooksDir is symlinked to by programs.claude-code.hooksDir.
  installedHooksDir = "${config.home.homeDirectory}/.claude/hooks";
in
{
  agents.tools.caveman = {
    packages = [ caveman-shrink ];
    docs.opencodeOnly = [ "${inputs.caveman}/src/rules/caveman-activate.md" ];
    hooks = {
      SessionStart = [
        {
          hooks = [
            {
              type = "command";
              command = ''${pkgs.nodejs}/bin/node "${installedHooksDir}/caveman-activate.js"'';
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
              command = ''${pkgs.nodejs}/bin/node "${installedHooksDir}/caveman-mode-tracker.js"'';
              timeout = 5;
              statusMessage = "Tracking caveman mode...";
            }
          ];
        }
      ];
    };
  };

  # Edge-case settings bypass the submodule shape — gated directly on enable.
  programs.claude-code = lib.mkIf cfg.enable {
    hooksDir = "${inputs.caveman}/src/hooks";
    settings.statusLine = {
      type = "command";
      command = ''bash "${installedHooksDir}/caveman-statusline.sh"'';
    };
  };
}
