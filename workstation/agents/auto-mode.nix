# Auto-mode classifier context for Claude Code.
#
# `/auto-mode-setup` normally writes this block into ~/.claude/settings.json,
# which fails here: that file is a read-only Nix store symlink. Regenerate the
# proposal with
#
#   claude -p "/auto-mode-setup --wizard posture=personal scope=all depth=both --propose"
#
# and transcribe the `proposal` object below. The literal "$defaults" entry
# keeps the shipped rules and appends ours; dropping it replaces them.
{
  programs.claude-code.settings.autoMode = {
    environment = [
      "### Org-wide"
      "**Organization**: None configured — this is a personal NixOS/Home Manager config repo (dot-emacs) plus a scattering of personal and one former-employer (Knowit-Objectnet) repos; no current employer/org context found"
      "**Cloud provider(s)**: None configured"
      "**Repository visibility**: PUBLIC — repo `ohaukeboe/dot-emacs` is confirmed public via gh. Note the org repo split also lists several other PUBLIC repos under the same account: `cosmic-pass`, `kotlin-lsp-flake`, `dig-kodeoppgave`, `oos`, `projection`, `zotra-server-flake`, `calibre-plugins`, `vanilla_pack`, `minecraft-docker`, `databricks-dataops-course`, `kfin`, `in3260-documentation`, `org-present`, `teacup-nethint`, `NETHINT`, `devilry-mode`. Any push to these publishes the content."
      "**Internal sharing / snippet hosting**: None configured — treat public paste/gist services as outside the trust boundary"
      "**Secrets management**: SOPS (workstation/sops.nix, sops/) plus git-agecrypt for lower-sensitivity private data (private/, git-agecrypt.toml); secrets-manager env markers SOPS_AGE_DIR and SOPS_AGE_KEY_FILE found in config scan; sensitive paths sops/home/secrets.yaml and sops/system/secrets.yaml, and gitignored .beads-credential-key / /secrets/.authinfo"
      "**Default / protected branches**: default branch `main`; gh reports no rulesets and no protected branches listed for `ohaukeboe/dot-emacs` — treat as genuinely unprotected (no ruleset caveat evidence here) but never push accidental history-rewrites regardless"
      "**CI/CD deploy targets**: None configured"
      "**Network posture**: None configured"
      "**Host containment**: None configured — assume Claude Code runs on an ordinary developer machine with open internet"
      "**Source control**: The trusted repo (github.com:ohaukeboe/dot-emacs.git) and its remote only — no additional orgs configured"
      "**Trusted internal domains**: None configured"
      "**Trusted cloud buckets**: None configured"
      "**Key internal services**: None configured"
      "**Internal package registry**: None configured"
      "**Sensitive data locations & audiences**: SOPS-encrypted secrets (sops/home/secrets.yaml, sops/system/secrets.yaml, sops/bootstrap/host-key.yaml), git-agecrypt-encrypted private/ data, .envrc, gitignored .beads-credential-key and /secrets/.authinfo — share only with the repo owner (oskar); never commit unencrypted"
      "**Data retention / declassification**: None configured"
      "**Sensitive remote targets**: any namespace, host, or container whose name carries `prod` or `production` as a whole word or name segment"
      "**Protected deployment namespaces / environments**: None configured — fall back to the Sensitive remote targets heuristic"
      "**Protected IaC scopes**: IAM, RBAC, networking, quota, and node-pool resources; anything whose name or tag carries `prod` or `production` as a whole word or name segment"
      "### User-specific"
      "**Primary use of Claude Code**: software development — personal NixOS/Home Manager literate-config maintenance, MCP server/skill registration, and issue tracking via beads (bd)"
      "**Trusted repo**: github.com:ohaukeboe/dot-emacs.git (public) — the agent's working directory and its origin remote; since this repo is public, only this repo's own work belongs in commits/pushes here — do not port in confidential material or content from the private Knowit-Objectnet or homestach/folindra sibling repos"
      "**Org-specific CLIs**: None configured — `bd` (beads issue tracker), `rtk` (token-optimized CLI proxy / hook rewrite of routine commands), and `nix`/`nix-shell`/`nixos-rebuild`/`just` are personal tooling conventions in this repo, not org-mandated"
      "routine under oskar/ prefix: nix build/eval targets, home-manager switch, and bd issue-tracker commands are routine in this repo's working tree"
    ];

    allow = [
      "$defaults"
      "Bash(bd ready:*)"
      "Bash(bd show:*)"
      "Bash(bd update:*)"
      "Bash(nix flake check:*)"
      "Bash(nix build:*)"
    ];

    soft_deny = [
      "$defaults"
      "Bash(git push --force:*)"
      "Bash(nixos-rebuild switch:*)"
    ];
  };
}
