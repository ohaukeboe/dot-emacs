{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.agents.tools.codeReviewGraph;

  version = "2.3.5";

  code-review-graph = pkgs.python3Packages.buildPythonPackage {
    pname = "code-review-graph";
    inherit version;
    pyproject = true;

    src = pkgs.fetchPypi {
      pname = "code_review_graph";
      inherit version;
      hash = "sha256-zXhk8fnObUzYU/nAS5dcaLfbLb58kueVbw5B8wMDurM=";
    };

    nativeBuildInputs = with pkgs.python3Packages; [
      hatchling
      pythonRelaxDepsHook
    ];

    pythonRelaxDeps = [
      "fastmcp"
      "tree-sitter-language-pack"
      "watchdog"
    ];

    propagatedBuildInputs = with pkgs.python3Packages; [
      mcp
      fastmcp
      tree-sitter
      tree-sitter-language-pack
      networkx
      igraph
      watchdog
    ];

    doCheck = false;
  };

  # Skills and hooks ship in the GitHub repo, not the PyPI sdist.
  upstream = pkgs.fetchFromGitHub {
    owner = "tirth8205";
    repo = "code-review-graph";
    rev = "v${version}";
    hash = "sha256-dbtvtxSi4S42sBkCBLtYPH3ck6f1gKsmvGmcrcBqcdU=";
  };

  crg = "${code-review-graph}/bin/code-review-graph";

  patchCommand = builtins.replaceStrings [ "code-review-graph" ] [ crg ];

  patchHookEntries = map (
    entry:
    entry
    // {
      hooks = map (h: h // { command = patchCommand h.command; }) entry.hooks;
    }
  );

  upstreamHooks = builtins.fromJSON (builtins.readFile "${upstream}/hooks/hooks.json");

  crgSkills = pkgs.runCommand "code-review-graph-skills" { } ''
    cp -r ${upstream}/skills $out
  '';
in
{
  # Preserve previous "commented out" semantic: off by default.
  # mkIf is applied per-field (not at the submodule level) so the system can
  # resolve `enable` without forcing the other field expressions, which would
  # trigger the upstream GitHub fetch.
  agents.tools.codeReviewGraph = {
    enable = lib.mkDefault false;
    packages = lib.mkIf cfg.enable [ code-review-graph ];
    skills = lib.mkIf cfg.enable [ crgSkills ];
    mcpServers = lib.mkIf cfg.enable {
      "code-review-graph" = {
        command = crg;
        args = [
          "serve"
          "--auto-watch"
        ];
      };
    };
    hooks = lib.mkIf cfg.enable (lib.mapAttrs (_: patchHookEntries) upstreamHooks);
  };
}
