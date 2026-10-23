#!/usr/bin/env bash
# Report, for every fix reference in this repo, whether the nixpkgs change it
# names has reached the pinned nixpkgs. See "Fix reference" in GLOSSARY.md.
#
#   just check-fixes            (or: nix run .#check-fixes)
#
# Run it from anywhere inside the repo, typically after `nix flake update`.
# A fix reference is owner/repo#N, written either as code
# (fixedBy = "NixOS/nixpkgs#N") or as a comment (# fixedBy: NixOS/nixpkgs#N),
# on one line. Git-tracked *.nix files are scanned; tests/ is skipped because
# its references are fixtures.
#
# A line matching `fixedBy *[:=]` that does not parse as a reference gets a
# warning on stderr. Only that form is checked, deliberately: code that merely
# mentions the attribute, such as `args ? fixedBy`, is not flagged.
#
# One line is printed per reference:
#
#   <category> <owner/repo#N> (<file:line>[, <file:line>...]): <advice>
#
# where <category> is one of
#   pinned-fixed     the fix commit is in the pinned nixpkgs
#   upstream-fixed   the fix commit is in nixos-unstable but not the pin
#   pending          open, or merged but not in nixos-unstable yet
#   closed-unmerged  a PR closed without merging
#   unknown          an issue closed with no linked commit
#
# An issue's events are read from the first page only (requests carry no query
# string, see GITHUB_API_URL), so an issue whose "closed" event lies beyond
# GitHub's first 30 events reports unknown.
#
# The report is advice, never a gate: the exit code is 0 whatever the
# categories, and non-zero only when the GitHub API cannot be read.
#
# Environment:
#   GITHUB_API_URL  API base URL (default https://api.github.com). Requests
#                   carry no query string, so a file:// tree laid out as API
#                   paths can stand in for it (tests/check-fixes.nix).
#   GITHUB_TOKEN    sent as a bearer token when set, for the higher rate
#                   limit. Nothing else is read for credentials: no gh
#                   config, no keyring.
set -euo pipefail

api=${GITHUB_API_URL:-https://api.github.com}
api=${api%/}
upstream=nixos-unstable
# The fix reference syntax, owner/repo#N, as an ERE. Substituted by flake.nix
# from lib/expiring-override.nix, its one definition.
ref_re='@fixReferencePattern@'

top=$(git rev-parse --show-toplevel)
cd "$top"

# GET an API URL (a path below $api, or an absolute URL) and print the body.
get() {
  local url=$1
  case $url in
  /*) url=$api$url ;;
  esac
  local args=(--silent --show-error --fail --location
    --header 'Accept: application/vnd.github+json'
    --header 'X-GitHub-Api-Version: 2022-11-28')
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    # Through a config on stdin so the token stays out of the process list.
    printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_TOKEN" |
      curl "${args[@]}" --config - -- "$url"
  else
    curl "${args[@]}" -- "$url"
  fi
}

pinned=$(jq -er '.nodes[.nodes.root.inputs.nixpkgs].locked.rev' flake.lock)

# --- Collect references: "<ref>\t<file:line>" per occurrence ---------------
scan() { # pattern; git grep exits 1 when nothing matches, which is fine
  git grep -n -I -E "$1" -- '*.nix' ':(exclude)tests/**' || [[ $? -eq 1 ]]
}
# A reference must end at a word boundary, so "#12x" is malformed, not #12.
ref_line_re="fixedBy *[:=] *\"?($ref_re)([^A-Za-z0-9._/#-]|\$)"
matches=$(scan "$ref_line_re")
refs=$(sed -E "s@^([^:]+):([0-9]+):.*$ref_line_re.*@\3\t\1:\2@" <<<"$matches")

# Lines that look like a reference but do not parse would be invisible here.
while IFS= read -r line; do
  [[ -n $line ]] || continue
  if ! grep -qE "$ref_line_re" <<<"$line"; then
    loc=${line%%:*}:$(cut -d: -f2 <<<"$line")
    text=$(cut -d: -f3- <<<"$line" | sed -E 's/^[[:space:]]+//')
    echo "warning: $loc: cannot parse fix reference: $text" >&2
  fi
done < <(scan 'fixedBy *[:=]')

# --- Report ------------------------------------------------------------------
report() { # category ref locations advice
  printf '%s %s (%s): %s\n' "$1" "$2" "$3" "$4"
}

# Print "yes" if commit $2 is contained in revision $3 of repo $1, else "no".
contains() {
  local status
  status=$(get "/repos/$1/compare/$2...$3" | jq -er '.status') || return
  case $status in
  ahead | identical) echo yes ;;
  *) echo no ;;
  esac
}

check_ref() { # ref locations
  local ref=$1 locs=$2
  local repo=${ref%#*} n=${ref##*#}
  local issue pr events sha in_pin in_upstream
  local merged
  issue=$(get "/repos/$repo/issues/$n") || return
  # The issues endpoint covers PRs too, with the same state.
  if [[ $(jq -er '.state' <<<"$issue") == open ]]; then
    report pending "$ref" "$locs" "still open"
    return
  fi
  if jq -e '.pull_request' <<<"$issue" >/dev/null; then
    pr=$(get "/repos/$repo/pulls/$n") || return
    # Anything but a boolean is an unexpected response, hence an error.
    merged=$(jq -r '.merged | if type == "boolean" then . else error("no boolean merged in PR response") end' <<<"$pr") || return
    if [[ $merged != true ]]; then
      report closed-unmerged "$ref" "$locs" "closed without merging, find the replacement PR"
      return
    fi
    sha=$(jq -er '.merge_commit_sha' <<<"$pr") || return
  else
    # The commit whose "fixes #N" closed the issue, if any. Followed through
    # the issue's own events_url rather than a path built here: that path
    # would sit below the issue's, which a file:// fixture cannot hold.
    events=$(get "$(jq -er '.events_url' <<<"$issue")") || return
    sha=$(jq -r '[.[] | select(.event == "closed")] | last | .commit_id // empty' <<<"$events") || return
    if [[ -z $sha ]]; then
      report unknown "$ref" "$locs" "closed, fix commit unknown, point me at the PR"
      return
    fi
  fi
  in_pin=$(contains "$repo" "$sha" "$pinned") || return
  if [[ $in_pin == yes ]]; then
    report pinned-fixed "$ref" "$locs" "fix is in the pinned nixpkgs, remove the workaround"
    return
  fi
  in_upstream=$(contains "$repo" "$sha" "$upstream") || return
  if [[ $in_upstream == yes ]]; then
    report upstream-fixed "$ref" "$locs" "fix is in $upstream but not the pin, run nix flake update"
  else
    report pending "$ref" "$locs" "merged, not in a channel yet"
  fi
}

failed=0
while IFS=$'\t' read -r ref locs; do
  [[ -n $ref ]] || continue
  check_ref "$ref" "$locs" || {
    echo "error: could not check $ref (see above)" >&2
    failed=1
  }
done < <(
  # One line per reference, its locations joined in file order.
  awk -F'\t' '
    !($1 in locs) { order[++n] = $1; locs[$1] = $2; next }
    { locs[$1] = locs[$1] ", " $2 }
    END { for (i = 1; i <= n; i++) print order[i] "\t" locs[order[i]] }
  ' <<<"$refs"
)
exit "$failed"
