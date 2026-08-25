#!/usr/bin/env bash
# Re-encrypt private/** for the recipients currently declared in
# git-agecrypt.toml and stage the result.
#
# Why this exists: git-agecrypt's clean filter reuses the ciphertext already in
# HEAD whenever one of the configured identities can decrypt it and the
# plaintext still matches. That is what keeps diffs stable, but it also means a
# recipient change in git-agecrypt.toml is silently ignored — `git add
# --renormalize private` gives you back the old blob with the old recipients.
#
# So we encrypt with age directly and write the blobs into the index with
# `git update-index --cacheinfo`, bypassing the filter.
#
# IMPORTANT: commit right after running this. Until the new ciphertext is in
# HEAD, any `git add` on these paths runs the clean filter again and restores
# the old blob.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

TOML=git-agecrypt.toml
[[ -f $TOML ]] || {
  echo "error: $TOML not found" >&2
  exit 1
}

TMPDIR_REKEY=$(mktemp -d)
trap 'rm -rf "$TMPDIR_REKEY"' EXIT

# path<TAB>recipient,recipient,...
mapfile -t entries < <(
  nix-shell -p python3 --run "python3 - <<'PY'
import tomllib
with open('$TOML', 'rb') as fh:
    cfg = tomllib.load(fh)['config']
for path, recipients in cfg.items():
    print(path + '\t' + ','.join(recipients))
PY"
)

[[ ${#entries[@]} -gt 0 ]] || {
  echo "error: no [config] entries in $TOML" >&2
  exit 1
}

for entry in "${entries[@]}"; do
  path=${entry%%$'\t'*}
  recipients=${entry#*$'\t'}
  [[ -f $path ]] || {
    echo "error: $path is missing from the working tree (is it decrypted?)" >&2
    exit 1
  }

  args=""
  IFS=',' read -ra recs <<<"$recipients"
  for r in "${recs[@]}"; do
    args+=" -r $r"
  done

  out="$TMPDIR_REKEY/$(echo "$path" | tr / _).age"
  nix-shell -p age age-plugin-yubikey --run "age $args -o $out $path"

  sha=$(git hash-object -w --no-filters "$out")
  git update-index --cacheinfo "100644,$sha,$path"
  echo "re-encrypted $path for ${#recs[@]} recipient(s) -> $sha"
done

echo
echo "Staged. Commit now — a stray 'git add' on these paths would undo it."
git status --short -- "${entries[@]%%$'\t'*}" || true
