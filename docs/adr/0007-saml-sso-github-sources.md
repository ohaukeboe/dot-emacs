# ADR 0007: Fetch SAML SSO-protected GitHub repos over git, not the API

**Status:** Accepted (2026-10-23).

## Context

Two external sources come from the `oslokommune` GitHub org: the
`punkt-skills` flake input and the `ok` CLI in `nvfetcher.toml`. Both repos
are public, but the org enforces SAML single sign-on. GitHub then rejects any
API request that carries a token not authorized for the org, even for public
data:

```
HTTP error 403
"Resource protected by organization SAML enforcement. You must grant your
Personal Access token access to this organization."
```

Only the work machine (dig-laptop) has an org-authorized token. Every other
host sends its own token, so `just update` failed in two places:

- `nix flake update` resolves `github:` inputs through
  `api.github.com/repos/<owner>/<repo>/commits/HEAD` with the `access-tokens`
  from `nix.conf`.
- `just update-sources` gives nvchecker the `gh auth token` keyfile, which
  avoids anonymous rate limits. nvchecker's `github` source queries
  `/releases/latest` with it.

The first workaround limited punkt-skills to dig-laptop and made `just update`
skip the input on other hosts. That did not cover nvfetcher, and it left the
lock file updatable from only one machine.

## Decision

**Sources from SAML SSO-protected orgs avoid the GitHub API.** They use the
git protocol, which needs no token for public repos and which the SSO
enforcement does not apply to.

- Flake inputs use `git+https://github.com/<owner>/<repo>` instead of
  `github:<owner>/<repo>`.
- nvfetcher entries get their version from
  `src.cmd = "git ls-remote --tags --refs <url> | … | sort -V | tail -n1"`
  instead of `src.github` / `src.github_tag`. nvfetcher's `src.git` cannot
  replace them, because it always tracks the latest commit and ignores
  `use_max_tag`. `fetch.github` can stay: it downloads the archive from
  `github.com`, not through the API.

All other sources keep `github:` and the token. Anonymous API access is
rate-limited, and their orgs do not enforce SSO.

Which machines install a source is a separate choice. punkt-skills stays on
dig-laptop because its skills are for work, not because of the fetch.

## Consequences

- `just update` and `just update-sources` work the same on every host, with
  no per-host input list.
- `git+https` fetches the whole repo history instead of a tarball, so it is
  slower and uses more disk space in the store. That is acceptable for small
  repos. A large repo would need `shallow=1`.
- The `src.cmd` tag filter replaces nvchecker's release semantics. A tag with
  no GitHub release (or a release marked pre-release with a plain `vX.Y.Z`
  tag) is picked up as the latest version.
- A new source from an SSO-enforcing org fails the same way until it gets the
  same treatment. The 403 body above identifies the case.
