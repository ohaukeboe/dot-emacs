---
name: add-skills-repo
description: Add a GitHub skills repository to the Nix home-manager config (skills.nix + flake.nix). Use this skill when the user wants to add skills from a GitHub repo, browse available skills from a repository, or configure a new skills source in their Nix/home-manager config. Trigger on phrases like "add skills from", "add this skills repo", "I want to use skills from github.com/X", "add X's skills to my nix config", or any request to wire up a new skill source into the Nix config.
---

Add a GitHub skills repository to `flake.nix` (as a non-flake input) and `workstation/agents/skills.nix` (as a `linkFarm` entry).

## Step 1: Resolve the repo URL

Accept any of these forms from the user:
- Nix flake format: `github:user/repo`
- HTTPS: `https://github.com/user/repo`
- Shorthand: `user/repo`

Normalize to `github:user/repo` for flake.nix. Derive an input name from the repo name — e.g., `my-skills` from `github:someone/my-skills`. If the derived name would collide with an existing input in `flake.nix`, suggest an alternative and confirm with the user.

## Step 2: Discover skills in the repo

Clone the repo to a temp dir and find all SKILL.md files:

```bash
REPO_DIR=$(mktemp -d)
git clone --depth=1 https://github.com/<user>/<repo> "$REPO_DIR" 2>&1
find "$REPO_DIR" -name "SKILL.md" | sort
```

For each SKILL.md, extract the `name` and `description` fields from the YAML frontmatter. Use this snippet:

```python
import sys, re

def extract_frontmatter(path):
    content = open(path).read()
    m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not m:
        return None, None
    fm = m.group(1)
    name_m = re.search(r'^name:\s*(.+)', fm, re.MULTILINE)
    desc_m = re.search(r'^description:\s*([\s\S]+?)(?=\n\w|\Z)', fm, re.MULTILINE)
    name = name_m.group(1).strip() if name_m else None
    if desc_m:
        # Collapse whitespace, take first sentence up to ~80 chars
        desc = ' '.join(desc_m.group(1).split())
        desc = re.split(r'(?<=[.!?])\s', desc)[0]
        if len(desc) > 80:
            desc = desc[:77] + '...'
    else:
        desc = None
    return name, desc
```

Use the `name` from frontmatter as the canonical skill name (not the directory name, unless frontmatter is missing).

## Step 3: Detect the directory layout

Determine the layout pattern from the SKILL.md paths:

| Layout | Example path | `subdir` |
|--------|-------------|---------|
| Flat | `skills/<name>/SKILL.md` | `"skills"` (default) |
| Nested by category | `skills/<cat>/<name>/SKILL.md` | `"skills/${cat}"` per entry |
| Plugin-style | `plugins/<name>/skills/<name>/SKILL.md` | `"plugins/<name>/skills"` per entry |
| Root | `<name>/SKILL.md` | `"."` |

If skills live in more than one category, use the per-entry `subdir` pattern (like `mattpocock-skills` in the existing config).

## Step 4: Update flake.nix

Read `/home/oskar/projects/dot-emacs/flake.nix`. If the input already exists, skip this step and say so.

Otherwise, add under `inputs`:

```nix
<input-name> = {
  url = "github:<user>/<repo>";
  flake = false;
};
```

Place it near the other skills inputs (after `llm-skills` or at the end of the inputs block).

## Step 5: Generate the skills.nix linkFarm entry

Read `/home/oskar/projects/dot-emacs/workstation/agents/skills.nix`. All skills **must be commented out by default** — the user uncomments the ones they want.

### Flat layout

```nix
# <repo-name> — uncomment skills you want
<camelCaseName>Skills = pkgs.linkFarm "<input-name>-skills" (
  map (mkSkillEntry { repo = inputs.<input-name>; }) [
    # { name = "<skill-1>"; }  # <one-line description>
    # { name = "<skill-2>"; }  # <one-line description>
  ]
);
```

### Nested layout (categories)

```nix
# <repo-name> — uncomment skills you want
# <cat1>: <name1>, <name2>
# <cat2>: <name3>
<camelCaseName>Skills = pkgs.linkFarm "<input-name>-skills" (
  map (e: mkSkillEntry { repo = inputs.<input-name>; } (e // { subdir = "skills/${e.subdir}"; }))
    [
      # -- <cat1> --
      # { name = "<skill-1>"; subdir = "<cat1>"; }  # <description>

      # -- <cat2> --
      # { name = "<skill-3>"; subdir = "<cat2>"; }  # <description>
    ]
);
```

**Formatting rules** — match the existing style in `skills.nix`:
- 2-space indentation inside the `let` block
- Comments use `#` with a space, aligned with the entry they describe
- Category headers use `# -- <name> --`
- Leave `disableAuto` off in the commented-out entries; the user can add it when uncommenting if they want to suppress automatic invocation

## Step 6: Wire into mergedSkills

Add the new variable to the `paths` list inside `mergedSkills`:

```nix
mergedSkills = pkgs.symlinkJoin {
  name = "merged-skills";
  paths = [
    ...existing paths...
    <camelCaseName>Skills   # ← new entry
  ]
  ++ config.agents.extraSkillPaths;
};
```

## Step 7: Apply and confirm

1. Write the updated `flake.nix` and `skills.nix`
2. Run `nix flake update <input-name>` to add the lock entry (or remind the user to do so if the Nix sandbox is unavailable)
3. Show the user a summary:
   - Input name added
   - Number of skills found
   - The full generated linkFarm block so they can see what's available
4. Remind them: uncomment an entry and run `home-manager switch` (or `nix run .#homeConfigurations.oskar.activationPackage`) to activate

## Edge cases

- **No SKILL.md files found**: Report this and ask if the URL is correct or if skills live at a non-standard path
- **Skill already present**: If the same skill name already appears in `mergedSkills`, warn about potential conflicts
- **Description field absent**: Use the directory name as a fallback and flag it with `# (no description)`
- **Very large repos**: Limit inspection to directories named `skills`, `skill`, `agents`, or `plugins` at depth ≤ 4 to avoid traversing unrelated code
