---
name: add-mcp-server
description: Register a new MCP (Model Context Protocol) server in the Nix home-manager config (workstation/agents/mcp-servers.nix), including file-based secret env vars, caveman-shrink token compression, and optional per-package derivations under workstation/agents/packages/. Use this skill whenever the user wants to add an MCP server, wire a new MCP integration into their Nix/home-manager config, expose a new tool to Claude Code or Opencode via MCP, register a stdio MCP server, set up an Emacs MCP stdio proxy, or mentions adding capabilities like "add the X MCP", "wire up MCP for Y", "I want to use github-mcp / kagi-mcp / chrome-devtools-mcp / etc.", or any request to expand the MCP-server inventory.
---

Register a new MCP server in `workstation/agents/mcp-servers.nix` using the helpers (`mkMcpServer`, `mkEmacsStdioServer`) and the `programs.mcp.servers` seam. If the server needs a build-from-source derivation, drop it in `workstation/agents/packages/<name>.nix`.

## When NOT to use this skill

- **Tool-integration that happens to also expose an MCP server** (e.g., `code-review-graph` is a CLI + MCP + skills bundle). Wire it through the tool submodule (`agents.tools.<toolName>.mcpServers = {...}`) so toggling `enable` removes the whole bundle atomically. The fold in `default.nix` collects per-tool `mcpServers` into `programs.mcp.servers` automatically.
- **HTTP / SSE-transport servers**. Current helpers assume stdio. For HTTP/SSE you must hand-roll the entry with the explicit `type = "http"` (or `"sse"`) field — see the upstream `programs.mcp.servers` schema in the home-manager module.

This skill covers the common case: a stdio MCP server registered globally (not tied to a single tool integration). A server only a few repositories need (a browser, a phone) can instead be opt-in per repository for Claude Code — see Step 4c.

## Step 1: Identify the server source

Classify before touching files:

| Source | Action |
|--------|--------|
| Already in nixpkgs (`pkgs.<name>`) | No derivation needed. Reference `pkgs.<name>` directly. |
| Already a flake output (e.g., `inputs.foo.packages.${pkgs.system}.default`) | Add the flake to `flake.nix` inputs; reference the package via `inputs.<name>`. |
| Python sdist on PyPI | Build with `buildPythonApplication` in `packages/<name>.nix`. See `packages/kagimcp.nix` for the pattern (`python312.override` for transitive-dep test skips). |
| npm package on the registry | Build with `buildNpmPackage` from an nvfetcher source (`nvSources.<name>`, see the add-package-source skill) + a checked-in lock file. See `packages/chrome-devtools-mcp.nix`. |
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
      # cfn-lint = expiringSkipTests pyprev.cfn-lint { brokenAt = "<ver>"; reason = "..."; };
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
{ buildNpmPackage, nvSources }:

buildNpmPackage {
  pname = "<name>";
  version = nvSources.<name>.version;
  src = nvSources.<name>.src;
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
| Secret env from a sops file | `env.ENV_NAME.file = config.sops.secrets."path/to/secret".path;` | Upstream home-manager reads the file at runtime, differently per consumer, so the value never reaches the Nix store. The `mkMcpServer` comment in `mcp-servers.nix` is the canonical account — read it there rather than restating it here. |

Both can compose (see `github-mcp` in current `mcp-servers.nix`: both an `env.<VAR>.file` secret and `shrink = true`).

If the server needs neither, you get a bare `{ command; args; }` entry — no shrink, no secret.

Non-secret vars go in the same `env` attrset as plain strings: `env = { LOG_LEVEL = "info"; };`. Literal strings and `{ file = ...; }` references can be mixed freely.

## Step 4: Pick the helper

### 4a. Standard MCP server (`mkMcpServer`)

```nix
"<server-name>" = mkMcpServer {
  command = "<absolute-or-PATH binary>";  # e.g. "github-mcp-server" or "${pkg}/bin/foo"
  args = [ "stdio" "--flag" "value" ];    # optional
  env = {                                 # optional; literals and file refs can mix
    LOG_LEVEL = "info";
    GITHUB_PERSONAL_ACCESS_TOKEN.file = config.sops.secrets."authinfo/github_pat".path;
  };
  shrink = true;                          # optional, default false
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

### 4c. Opt-in per repository (Claude Code only)

Every global server's tool list and instructions load into every Claude Code session. If only some repositories need the server, make it opt-in instead of adding it to `programs.mcp.servers`:

1. Add the `mkMcpServer` entry to the `optInServers` attrset in the `let` of `mcp-servers.nix`.
2. Add its name to the enum of `options.agents.mcp.optIn.servers` and to that option's `default`.
3. Add a plugin name to `pluginNames`, e.g. `"<server-name>" = "hm-<short>";`. It must differ from every skill name, because plugins and skills share `~/.claude/skills`. The tool prefix becomes `mcp__plugin_hm-<short>_<server-name>__`.

The module then builds a default-off `hm-<short>` plugin holding the server, writes `enabledPlugins."hm-<short>@skills-dir" = false` to the user settings, and still gives the server to Opencode, which has no per-repository switch. A repository turns it on with this in its `.claude/settings.local.json` (in a repository whose sandbox write-denies that file, the user makes the edit):

```json
{ "enabledPlugins": { "hm-<short>@skills-dir": true } }
```

The plugin's `.mcp.json` carries `command` and `args` only, so an opt-in server cannot take `env` (secret or literal). Keep such a server global, or wrap the binary so it reads its own secret.

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

Then `nix flake update <name>`.

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
4. **Inspect the generated config** (sanity-check secret-env / shrink wiring). The
   registry itself never holds a wrapper — each consumer decides. Read the built
   outputs rather than `config.programs.mcp.servers`:
   ```bash
   out=$(nix build --no-link --print-out-paths \
     .#homeConfigurations."oskar@x86_64-linux".activationPackage)
   # Central registry: expect a "{file:/path/to/secret}" token, never the value
   cat "$out"/home-files/.config/mcp/mcp.json
   # Claude Code: secret-bearing servers point at /nix/store/...-mcp-<name>-wrapper
   cat "$out"/home-files/.claude/skills/claude-code-home-manager/.mcp.json
   # Opencode: same "{file:...}" token, under "environment"
   cat "$out"/home-files/.config/opencode/opencode.json
   ```
   A secret's **value** must appear in none of these. Seeing the path is correct.
5. **Format**: `nix fmt -- workstation/agents/mcp-servers.nix` (treefmt).
6. **Apply**: tell the user to run `sudo nixos-rebuild switch --flake .#<hostname>`. The new server appears in Claude Code + Opencode automatically — both `programs.claude-code.enableMcpIntegration` and `programs.opencode.enableMcpIntegration` are `true` in `mcp-servers.nix`.

## Edge cases

- **`npmDepsHash` mismatch**: leave the hash as `""` first; the failing build prints the expected hash. Substitute, rebuild.
- **PyPI sdist test failures via transitive deps**: use `python<NN>.override { packageOverrides = pyfinal: pyprev: { <dep> = expiringSkipTests pyprev.<dep> { brokenAt = "<ver>"; reason = "..."; }; }; }`. See `packages/kagimcp.nix` and `lib/expiring-override.nix`.
- **Server needs more than env-from-file** (e.g., a config file written to disk): the helper covers env only. For richer setup, either pre-wrap the binary in a derivation or write a small `pkgs.writeShellScript` directly and pass it as `command`.
- **Multiple servers share a wrapper pattern not covered by the helpers**: extend the helper rather than duplicating wrapper logic inline. "Two adapters = real seam".
- **Stop using a server**: just delete its entry from `programs.mcp.servers` (and its `home.packages` entry if present). For an opt-in server, also drop it from the `agents.mcp.optIn.servers` enum and `pluginNames`.
- **Make an opt-in server global again**: remove it from `agents.mcp.optIn.servers` (the list, not the enum), for all repositories or on one machine. It then joins `programs.mcp.servers` unchanged.
