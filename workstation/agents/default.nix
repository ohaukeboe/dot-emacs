{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  isLinux = pkgs.stdenv.isLinux;
  isDarwin = pkgs.stdenv.isDarwin;
  chrome-devtools-mcp = pkgs.buildNpmPackage {
    pname = "chrome-devtools-mcp";
    version = "1.0.1";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-1.0.1.tgz";
      hash = "sha256-8CyjSlq3caR9BbfmKJsAfSjVcMsNdwIlTeRctEaDra8=";
    };
    sourceRoot = "package";
    npmDepsFetcherVersion = 2;
    npmDepsHash = "sha256-v6ZX9uqsEtYwiDRLa95SieDu+5fzuZcJEHeNhoCmNSo=";
    npmFlags = [
      "--omit=dev"
      "--ignore-scripts"
    ];
    dontNpmBuild = true;
    preInstall = "mkdir -p node_modules";
    postPatch = "cp ${./chrome-devtools-mcp-lock.json} package-lock.json";
  };
  joinDocs = paths: lib.concatStringsSep "\n" (map (p: builtins.readFile p) paths);
  combinedDocs = joinDocs ([ ./agents-global.md ] ++ config.agents.extraClaudeDocs);
  claudeDocs = joinDocs (
    [ ./agents-global.md ] ++ config.agents.extraClaudeDocs ++ config.agents.extraClaudeOnlyDocs
  );
  opencodeDocs = joinDocs (
    [ ./agents-global.md ] ++ config.agents.extraClaudeDocs ++ config.agents.extraOpencodeDocs
  );
in
{
  options.agents = {
    extraClaudeDocs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };
    extraOpencodeDocs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };
    extraClaudeOnlyDocs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };
  };

  imports = [
    ./beads.nix
    ./caveman.nix
    # ./code-review-graph.nix
    ./mcp-servers.nix
    ./rtk.nix
    ./skills.nix
    ./subagents.nix
  ];

  config = {
    home.packages =
      with pkgs;
      lib.lists.flatten [
        (lib.optional isLinux wl-clipboard) # used by agent-shell
        (lib.optional isDarwin pngpaste) # used by agent-shell

        ### Coding agent ###
        claude-agent-acp
        aider-chat-full # another AI thingy

        ### Agent Tools ###
        chrome-devtools-mcp
        mcp-nixos
        github-mcp-server
      ];

    programs.claude-code.enable = true;
    programs.claude-code.settings.remoteControlAtStartup = true;
    programs.claude-code.settings.skipAutoPermissionPrompt = true;
    programs.claude-code.settings.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS = "1";
    programs.claude-code.settings.skillListingBudgetFraction = 0.02;
    programs.claude-code.context = claudeDocs;

    programs.opencode.enable = true;
    programs.opencode.settings = {
      model = "openrouter/anthropic/claude-sonnet-4.6";
    };
    programs.opencode.context = opencodeDocs;

    home.file = {
      "${config.home.homeDirectory}/.agents/AGENTS.md".text = combinedDocs;

      ".aider.conf.yml".source = (pkgs.formats.yaml { }).generate "aider-conf" {
        cache-prompts = true;
        cache-keepalive-pings = 5;
        code-theme = "monokai";
        auto-commits = false;
        model = "openrouter/anthropic/claude-sonnet-4.6";
        weak-model = "openrouter/anthropic/claude-haiku-4.5";
      };
    };
  };
}
