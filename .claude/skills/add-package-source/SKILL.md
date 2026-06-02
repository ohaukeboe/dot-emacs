---
name: add-package-source
description: Add an external package/source to this Nix home-manager config — choosing between nvfetcher (version-pinned GitHub releases/tags, npm, PyPI source) and a flake input (upstream-is-a-flake, or `flake = false` for HEAD-tracked plain source). Use this skill whenever the user wants to add, pin, vendor, or wire in an external package, dependency, source, repo, Emacs package, plugin, or upstream tool into their Nix/home-manager config. Trigger on phrases like "add a package source", "pin this release", "vendor this repo", "add nvfetcher source", "add a flake input", "track this GitHub repo", "I want to use <github.com/X> in my config", "add this Emacs package", or any request to bring a new external source into flake.nix / nvfetcher.toml.
---

Add a new external source to this repo's two source-management seams: **nvfetcher** (`nvfetcher.toml` → `_sources/generated.nix`, exposed as the `pkgs.nvSources` overlay) for version-pinned sources, or a **flake input** (`flake.nix`) for upstream flakes and HEAD-tracked plain repos.

This skill covers adding the *source/pin* — the fetch layer. Turning a source into a built package (`trivialBuild`, `buildNpmPackage`, `buildPythonApplication`, `callPackage`) is downstream; for MCP-server build derivations see the **add-mcp-server** skill, and for skill repos see **add-skills-repo**. This skill points at the consumption shape but its job is to get the source correctly pinned and evaluable.

## Step 1: Choose the mechanism

The decision is about **how the source moves over time**, not just where it lives. Walk this in order — the first match wins:

| # | Condition                                                                                                                   | Mechanism                               | Moves on                  |
|---|-----------------------------------------------------------------------------------------------------------------------------|-----------------------------------------|---------------------------|
| 1 | Upstream **is itself a Nix flake** and you want its outputs (`packages`, `homeModules`, `overlays`)                         | **flake input** (no `flake = false`)    | `nix flake update <name>` |
| 2 | You want a **specific pinned version** — a GitHub release, a GitHub tag, an npm version, a PyPI/GitHub source built locally | **nvfetcher** entry in `nvfetcher.toml` | `just update-sources`     |
| 3 | Plain source repo, **no usable releases/tags**, you want to track its branch HEAD                                           | **flake input** with `flake = false`    | `nix flake update <name>` |

Rules of thumb that disambiguate the common confusions:

- **"GitHub releases or similar" → nvfetcher.** Releases, tags, npm registry versions, PyPI versions are all version-pinned and belong in nvfetcher. nvfetcher records an exact rev + hash and bumps deterministically on `just update-sources`. This is the default for anything that publishes versions.
- **Upstream provides a flake you consume → flake input**, even though it's on GitHub. The signal is: you write `inputs.<name>.packages.${system}.default` / `inputs.<name>.homeModules.x` rather than building the source yourself. Examples in this repo: `zen-browser`, `kotlin-lsp`, `zotra-server`, `calibre-plugins`, `codebase-memory-mcp`.
- **No usable release AND you build it yourself → `flake = false`.** Two sub-cases:
  - *Tracking HEAD is what you want* (branch advances, no meaningful version) → flake input, `flake = false`. Examples: `claude-code-ide-src`, `gptel-quick-src`, `consult-mu-src`, the skills repos (`anthropics-skills`, `caveman`, …).
  - *You want a pinned tag/release of plain source* → that's case 2, **prefer nvfetcher** (e.g. `pgmacs`, `lsp-ltex-plus`, `code-review-graph`). nvfetcher keeps the pin out of `flake.lock` churn and bumps on its own cadence.

If the user is unsure which they want for a release-publishing repo, default to **nvfetcher** — that's the established convention here (see the `nvfetcher` memory / `bd memories nvfetcher`).

---

## Path A — nvfetcher (version-pinned)

### A1. Pick the fetch strategy

nvfetcher needs two things per entry: where to *fetch* the artifact, and what to *poll* for the latest version. Match the source type:

| Source type                                      | `nvfetcher.toml` entry shape                                                                                       |
|--------------------------------------------------|--------------------------------------------------------------------------------------------------------------------|
| GitHub **latest release**                        | `fetch.github = "owner/repo"` + `src.github = "owner/repo"`                                                        |
| GitHub **tags** (no releases, just tags)         | `fetch.github = "owner/repo"` + `src.github_tag = "owner/repo"`                                                    |
| GitHub **release asset** (specific download URL) | `fetch.url = ".../$ver/asset-$ver.zip"` + `src.github_tag = "owner/repo"` (add `src.include_regex` to filter tags) |
| **npm** package                                  | `fetch.url = "https://registry.npmjs.org/<pkg>/-/<pkg>-$ver.tgz"` + `src.cmd = "npm view <pkg> version"`           |

`$ver` in `fetch.url` is substituted with the resolved version. `src.include_regex` narrows which tags count as "latest" (needed for monorepos that tag many components — see `calibre-open-with`).

### A2. Add the entry

Edit `/home/oskar/projects/dot-emacs/nvfetcher.toml`. Add the entry alphabetically-ish near related entries, **with a comment explaining the choice** — every existing entry carries a one-line rationale, match that. Example (GitHub tags, no releases):

```toml
# <pkg> publishes no GitHub releases, only tags -> github_tag.
[<pkg>]
fetch.github = "owner/repo"
src.github_tag = "owner/repo"
```

### A3. Regenerate `_sources/`

```bash
just update-sources
```

This runs `nvfetcher` in a `nix-shell` (with `nodejs` on PATH for any `src.cmd` npm lookups) and rewrites `_sources/generated.nix` + `_sources/generated.json` with the resolved version + sha256. **Do not hand-edit `generated.nix`** — it's machine-generated.

> If the Nix sandbox / network is unavailable, tell the user to run `just update-sources` themselves; you cannot fabricate the hash.

### A4. Consume it

The new source appears as `pkgs.nvSources.<pkg>` with `.src` and `.version` attrs. Wire it where the package is built:

- **Emacs package** (`workstation/home.nix`, in the `trivialBuild` list):
  ```nix
  (epkgs.trivialBuild {
    pname = "<pkg>";
    version = pkgs.nvSources.<pkg>.version;
    src = pkgs.nvSources.<pkg>.src;
    packageRequires = [ <deps> ];
  })
  ```
- **npm / Python build** (a `packages/<pkg>.nix` derivation taking `nvSources`): see `workstation/agents/packages/chrome-devtools-mcp.nix` and the **add-mcp-server** skill.
- **Raw source path** (e.g. a plugin zip): `pkgs.nvSources.<pkg>.src` (see `workstation/calibre/default.nix`).

### A5. npm caveat

For npm packages, nvfetcher only hashes the **source tarball**. `buildNpmPackage`'s `npmDepsHash` (and any checked-in lock file like `chrome-devtools-mcp-lock.json`) must still be regenerated **by hand** on a version bump — nvfetcher does not touch them. Flag this to the user when adding an npm source.

---

## Path B — flake input

### B1. Add the input

Edit `/home/oskar/projects/dot-emacs/flake.nix`. Derive an input name from the repo (e.g. `foo-bar` → `fooBar` or `foo-bar`; match the casing of neighbours). If the name collides with an existing input, propose an alternative and confirm.

**Upstream is a flake** (you want its outputs) — follow nixpkgs where it makes sense:
```nix
<name> = {
  url = "github:owner/repo";
  inputs.nixpkgs.follows = "nixpkgs";   # only if upstream declares a nixpkgs input
};
```
Pin a tag/ref when upstream publishes them: `url = "github:owner/repo/v1.0.0";` (like `lanzaboote`).

**Plain source, track HEAD** (`flake = false`):
```nix
<name> = {
  url = "github:owner/repo";
  flake = false;
};
```
Place skill/source-only inputs near the existing `flake = false` cluster (after `llm-skills` / the `-src` emacs inputs).

### B2. If it's a flake with outputs, thread it through

If the input is consumed in a config module, add it to the `outputs` destructure / `inherit` lists that feed `mkHomeConfiguration` / `mkNixosConfiguration` — but most inputs are reached lazily via the `inputs` arg already passed through `extraSpecialArgs`/`specialArgs`, so you usually just reference `inputs.<name>` directly in the consuming module. Check how a sibling input is wired before adding plumbing.

### B3. Consume it

- Flake output: `inputs.<name>.packages.${pkgs.system}.default`, `inputs.<name>.homeModules.x`, etc.
- `flake = false` source: `inputs.<name>` is a path to the source tree — use as `src = inputs.<name>;` in a `trivialBuild`/`callPackage`, or `"${inputs.<name>}/subpath"`.

### B4. Lock it

```bash
nix flake update <name>      # adds/updates the flake.lock entry
```

---

## Step 3 (both paths): stage, build, verify

Nix flake evaluation **only sees git-tracked files**. After editing/creating files, `git add` them before building, or evaluation fails with `"... is not tracked by Git"`:

```bash
git add nvfetcher.toml _sources/ flake.nix flake.lock   # whichever changed
```

Then test-build the activation package (concrete attr avoids needing `--impure`):

```bash
nix build '.#homeConfigurations."oskar@x86_64-linux".activationPackage'
```

For an nvfetcher source you can sanity-check the pin resolved:

```bash
nix eval --raw '.#homeConfigurations."oskar@x86_64-linux".pkgs.nvSources.<pkg>.version' 2>/dev/null \
  || grep -A6 "<pkg> = {" _sources/generated.nix
```

Format before finishing (treefmt reformats across all files — revert stray churn):

```bash
nix fmt
```

## Step 4: summarize

Report to the user:
- Which mechanism was chosen and **why** (the deciding condition from Step 1)
- The exact entry/input added
- For nvfetcher: the resolved version + that future bumps come from `just update-sources` (and the npm `npmDepsHash` caveat if applicable)
- For flake inputs: that future bumps come from `nix flake update <name>`
- The remaining consumption wiring still needed (build derivation, module reference) if this skill only added the source

## Edge cases

- **Release vs. tag ambiguity on GitHub**: if `src.github` (latest release) yields nothing, the repo likely only tags without publishing releases — switch to `src.github_tag`. `pgmacs` and `lsp-ltex-plus` sit on opposite sides of this.
- **Monorepo tagging many components**: use `src.include_regex` to isolate the relevant tag prefix (see `calibre-open-with`'s `open_with-.*`).
- **Upstream is a flake but you only want its source, not its outputs**: still prefer the plain flake input without `flake = false` if it locks cleanly; only set `flake = false` if evaluating upstream's flake is undesirable (heavy inputs, broken eval).
- **Source needs a private/secret fetch**: out of scope here — sources are public. Secrets are handled via SOPS (`workstation/sops.nix`), not the source layer.
- **`just update-sources` needs network**: in an offline/sandboxed run you cannot resolve the hash; hand the command to the user rather than guessing.
