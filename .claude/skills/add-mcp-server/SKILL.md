---
name: add-mcp-server
description: Register a new MCP (Model Context Protocol) server in the Nix home-manager config (workstation/agents/mcp-servers.nix), including secret-env wrapping, caveman-shrink token compression, and optional per-package derivations under workstation/agents/packages/. Use this skill whenever the user wants to add an MCP server, wire a new MCP integration into their Nix/home-manager config, expose a new tool to Claude Code or Opencode via MCP, register a stdio MCP server, set up an Emacs MCP stdio proxy, or mentions adding capabilities like "add the X MCP", "wire up MCP for Y", "I want to use github-mcp / kagi-mcp / chrome-devtools-mcp / etc.", or any request to expand the MCP-server inventory.
---

Register a new MCP server in `workstation/agents/mcp-servers.nix` using the post-refactor helpers (`mkMcpServer`, `mkEmacsStdioServer`) and the `programs.mcp.servers` seam. If the server needs a build-from-source derivation, drop it in `workstation/agents/packages/<name>.nix`.

## When NOT to use this skill

- **Tool-integration that happens to also expose an MCP server** (e.g., `code-review-graph` is a CLI + MCP + skills bundle). Wire it through the tool submodule (`agents.tools.<toolName>.mcpServers = {...}`) so toggling `enable` removes the whole bundle atomically. The fold in `default.nix` collects per-tool `mcpServers` into `programs.mcp.servers` automatically.
- **HTTP / SSE-transport servers**. Current helpers assume stdio. For HTTP/SSE you must hand-roll the entry with the explicit `type = "http"` (or `"sse"`) field — see the upstream `programs.mcp.servers` schema in the home-manager module.

This skill covers the common case: a stdio MCP server registered globally (not tied to a single tool integration).

## Step 1: Identify the server source

Classify before touching files:

| Source | Action |
|--------|--------|
| Already in nixpkgs (`pkgs.<name>`) | No derivation needed. Reference `pkgs.<name>` directly. |
| Already a flake output (e.g., `inputs.foo.packages.${pkgs.system}.default`) | Add the flake to `flake.nix` inputs; reference the package via `inputs.<name>`. |
| Python sdist on PyPI | Build with `buildPythonApplication` in `packages/<name>.nix`. See `packages/kagimcp.nix` for the pattern (`python312.override` for transitive-dep test skips). |
| npm package on the registry | Build with `buildNpmPackage` + `fetchurl` + a checked-in `package-lock.json`. See `packages/chrome-devtools-mcp.nix`. |
| Source on GitHub (Go/Rust/etc.) | Either get it into nixpkgs upstream, or write a `pkgs.callPackage` derivation in `packages/<name>.nix`. |
| Emacs-side stdio (function in user's Emacs) | No package — use `mkEmacsStdioServer` (Step 4b). |

## Step 2: Decide on a package derivation

If the source isn't already a usable package, create `workstation/agents/packages/<name>.nix` and reference it via `pkgs.callPackage`.

### Python example (`packages/kagimcp.nix` shape)

```nix
{
  python312,
  src,
}:

let
  pythonOverridden = python312.override {
    packageOverrides = pyfinal: pyprev: {
      # only if a transitive dep needs `doCheck = false;` or similar
      # cfn-lint = pyprev.cfn-lint.overridePythonAttrs (_: { doCheck = false; });
    };
  };
in
pythonOverridden.pkgs.buildPythonApplication {
  pname = "<name>";
  version = "<version>";
  pyproject = true;
  inherit src;
  build-system = with pythonOverridden.pkgs; [ hatchling ];
  dependencies = with pythonOverridden.pkgs; [
    # runtime deps
  ];
  doCheck = false;
}
```

In `mcp-servers.nix`, call it: `pkgs.callPackage ./packages/<name>.nix { src = inputs.<flakeInputName>; }`.

### npm example (`packages/chrome-devtools-mcp.nix` shape)

```nix
{ buildNpmPackage, fetchurl }:

buildNpmPackage {
  pname = "<name>";
  version = "<version>";
  src = fetchurl {
    url = "https://registry.npmjs.org/<name>/-/<name>-<version>.tgz";
    hash = "sha256-...";  # get with: nix-prefetch-url --type sha256 <tgz-url>
  };
  sourceRoot = "package";
  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-...";   # leave empty first, rebuild → nix prints expected hash
  npmFlags = [ "--omit=dev" "--ignore-scripts" ];
  dontNpmBuild = true;
  preInstall = "mkdir -p node_modules";
  postPatch = "cp ${../<name>-lock.json} package-lock.json";
}
```

Generate the lock file once with `npm install --package-lock-only` outside the Nix sandbox and check it in under `workstation/agents/<name>-lock.json`.

Call site: `pkgs.callPackage ./packages/<name>.nix { }`.

### Important — git-add new files immediately

Nix flake evaluation only sees git-tracked files. After creating `packages/<name>.nix` (or any new lock-file alongside it), `git add` it **before** running `nix build` / `nix flake check`, or evaluation will fail with "no such file."

## Step 3: Identify wrapping needs

Two orthogonal needs the helpers cover automatically:

| Need | Flag | Mechanic |
|------|------|----------|
| Token compression (most chatty MCP servers benefit) | `shrink = true` | Prepends `caveman-shrink` to the command line. |
| Secret env from a sops file | `secretEnvFiles = { ENV_NAME = config.sops.secrets."path/to/secret".path; };` | Generates a `pkgs.writeShellScript` wrapper that `cat`s the file, exports the var, then `exec`s the underlying command. |

Both can compose (see `github-mcp` in current `mcp-servers.nix`: both `secretEnvFiles` and `shrink = true`).

If the server needs neither, you get a bare `{ command; args; }` entry — no wrapper script, no shrink.

If it needs **plain `env = { ... }` vars** (non-secret), pass `env = { FOO = "bar"; };` — works in all three branches.

## Step 4: Pick the helper

### 4a. Standard MCP server (`mkMcpServer`)

```nix
"<server-name>" = mkMcpServer {
  name           = "<server-name>";              # used as wrapper-script name
  command        = "<absolute-or-PATH binary>";  # e.g. "github-mcp-server" or "${pkg}/bin/foo"
  args           = [ "stdio" "--flag" "value" ]; # optional
  env            = { LOG_LEVEL = "info"; };      # optional, non-secret env
  secretEnvFiles = {                              # optional
    GITHUB_PERSONAL_ACCESS_TOKEN = config.sops.secrets."authinfo/github_pat".path;
  };
  shrink         = true;                          # optional, default false
};
```

### 4b. Emacs stdio MCP server (`mkEmacsStdioServer`)

Use when the server is an Emacs init/stop pair driven by `${emacsConfig}/emacs-mcp-stdio.sh`:

```nix
"<server-name>" = mkEmacsStdioServer {
  name          = "<server-name>";          # also becomes --server-id
  initFunction  = "<elisp-init-fn>";
  stopFunction  = "<elisp-stop-fn>";
  shrink        = true;                      # optional, default true for emacs servers
};
```

This expands to `mkMcpServer` under the hood with the standard launcher script and the three `--init-function=`, `--stop-function=`, `--server-id=` flags. Don't reimplement the launcher invocation by hand.

## Step 5: Register the package in `home.packages` (if applicable)

If the server binary comes from a derivation built in `mcp-servers.nix` (Python/npm/etc. via `callPackage`), and the binary is a top-level path (not a `${pkg}/bin/foo` already substituted into the command), add it to the `home.packages` list at the top of `mcp-servers.nix`:

```nix
home.packages = [
  chrome-devtools-mcp
  pkgs.mcp-nixos
  pkgs.github-mcp-server
  # <your new package here, if it needs to be on PATH>
];
```

Skip this step if you reference the binary by absolute store path (`command = "${pkg}/bin/foo";`) — the closure keeps it alive without exposing it on `PATH`.

## Step 6: Wire a flake input (if from GitHub)

If you used `inputs.<name>` in Step 2, edit `/home/oskar/projects/dot-emacs/flake.nix`:

```nix
<name> = {
  url = "github:<user>/<repo>";
  flake = false;          # or omit if upstream is a flake
};
```

Then `nix flake lock --update-input <name>` (or `nix flake update <name>` on older nix).

## Step 7: Apply and verify

1. **Stage everything** (Nix only evaluates git-tracked files):
   ```bash
   git add workstation/agents/packages/<name>.nix \
           workstation/agents/<name>-lock.json \
           workstation/agents/mcp-servers.nix \
           flake.nix flake.lock
   ```
2. **Evaluate** the server list to confirm it appears:
   ```bash
   nix eval --impure --raw \
     .#homeConfigurations."oskar@x86_64-linux".config.programs.mcp.servers \
     --apply 'servers: builtins.concatStringsSep "\n" (builtins.attrNames servers)'
   ```
3. **Build** the activation package:
   ```bash
   nix build .#homeConfigurations."oskar@x86_64-linux".activationPackage
   ```
4. **Inspect the generated wrapper** (sanity-check secret-env / shrink wiring):
   ```bash
   nix eval --raw .#homeConfigurations."oskar@x86_64-linux".config.programs.mcp.servers."<server-name>".command
   # if it points to /nix/store/...-<name>-mcp, cat it to see the wrapper
   ```
5. **Format**: `nix fmt -- workstation/agents/mcp-servers.nix` (treefmt).
6. **Apply**: tell the user to `home-manager switch` (or whatever their activation entry is). The new server appears in Claude Code + Opencode automatically — both `programs.claude-code.enableMcpIntegration` and `programs.opencode.enableMcpIntegration` are already `true` in the refactored `mcp-servers.nix`.

## Edge cases

- **`npmDepsHash` mismatch**: leave the hash as `""` first; the failing build prints the expected hash. Substitute, rebuild.
- **PyPI sdist test failures via transitive deps**: use `python<NN>.override { packageOverrides = pyfinal: pyprev: { <dep> = pyprev.<dep>.overridePythonAttrs (_: { doCheck = false; }); }; }`. The kagimcp derivation has the canonical example (cfn-lint chain).
- **Server needs more than env-from-file** (e.g., a config file written to disk): the helper covers env only. For richer setup, either pre-wrap the binary in a derivation or write a small `pkgs.writeShellScript` directly and pass it as `command`.
- **Multiple servers share a wrapper pattern not covered by the helpers**: extend the helper rather than duplicating wrapper logic inline. "Two adapters = real seam" — that's the whole point of the post-refactor shape.
- **Stop using a server**: just delete its entry from `programs.mcp.servers` (and its `home.packages` entry if present). No other refactor surface to touch.
