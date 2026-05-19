{
  lib,
  pkgs,
  ...
}:
let
  code-review-graph = pkgs.python3Packages.buildPythonPackage rec {
    pname = "code-review-graph";
    version = "2.3.3";
    pyproject = true;

    src = pkgs.fetchPypi {
      pname = "code_review_graph";
      inherit version;
      hash = "sha256-cF/2RopuAx8UikOUi7nLv1oj3ST6uhjrzDsFdMGmofc=";
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
in
{
  home.packages = [ code-review-graph ];

  programs.claude-code.settings.mcpServers."code-review-graph" = {
    command = "${code-review-graph}/bin/code-review-graph";
    args = [ "serve" ];
    type = "stdio";
  };
}
