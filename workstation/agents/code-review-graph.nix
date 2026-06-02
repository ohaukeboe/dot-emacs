{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.agents.tools.codeReviewGraph;

  # Single GitHub source for both the Python package and the skills/hooks that
  # ship only in the repo (not the PyPI sdist) — kept in lockstep by nvfetcher.
  src = pkgs.nvSources.code-review-graph.src;
  version = pkgs.nvSources.code-review-graph.version;

  code-review-graph = pkgs.python3Packages.buildPythonPackage {
    pname = "code-review-graph";
    inherit version src;
    pyproject = true;

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

  crg = "${code-review-graph}/bin/code-review-graph";

  patchCommand = builtins.replaceStrings [ "code-review-graph" ] [ crg ];

  patchHookEntries = map (
    entry:
    entry
    // {
      hooks = map (h: h // { command = patchCommand h.command; }) entry.hooks;
    }
  );

  upstreamHooks = builtins.fromJSON (builtins.readFile "${src}/hooks/hooks.json");

  crgSkills = pkgs.runCommand "code-review-graph-skills" { } ''
    cp -r ${src}/skills $out
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
