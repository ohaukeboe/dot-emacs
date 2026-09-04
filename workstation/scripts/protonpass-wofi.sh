# Quick access to Proton Pass items from a Wayland launcher.
#
# Pick an item, pick a field, and the value goes to the clipboard and is
# cleared again after a timeout. Item titles are cached because listing them
# hits the network; secrets are never cached and never passed as argv (which
# would be world-readable in /proc), only piped over stdin.
#
# Bound to a hotkey this fills the same role as a menu-bar quick-access app.

set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/protonpass-wofi"
CACHE_FILE="$CACHE_DIR/items.json"
CACHE_TTL="${PROTONPASS_WOFI_CACHE_TTL:-900}"
CLEAR_AFTER="${PROTONPASS_WOFI_CLEAR_AFTER:-45}"

# Overridable so the flow can be exercised without a compositor: any command
# reading newline-separated entries on stdin and echoing one back works.
MENU="${PROTONPASS_WOFI_MENU:-wofi --dmenu --insensitive --width=700 --height=450 --prompt}"

REFRESH_ENTRY="Refresh item list"

# Scratch directory for a rebuild, cleaned up however the script ends. A RETURN
# trap cannot do this: it fires after the function's locals are already gone.
SCRATCH=""
cleanup() {
  if [ -n "$SCRATCH" ]; then
    rm -rf "$SCRATCH"
  fi
}
trap cleanup EXIT

notify() {
  if command -v notify-send >/dev/null; then
    notify-send --app-name="Proton Pass" --expire-time=3000 "$1" "${2-}"
  fi
}

die() {
  notify "Proton Pass" "$1"
  echo "$1" >&2
  exit 1
}

menu() {
  # $1 is the prompt; entries arrive on stdin. Dismissing wofi with Escape
  # exits non-zero, which is a cancel rather than an error, so it is reported
  # the same way as an empty pick: no output, and callers stop there. Running
  # inside a command substitution means exiting from here would only leave the
  # subshell, so the decision has to belong to the caller.
  local prompt="$1" choice
  choice=$($MENU "$prompt") || return 0
  printf '%s' "$choice"
}

# Item and share IDs are base64 and frequently start with "-", which clap reads
# as a flag. Every pass-cli option below therefore uses --flag=value.
require_session() {
  pass-cli info >/dev/null 2>&1 ||
    die "Not logged in. Run 'pass-cli login' first."
}

build_index() {
  local vaults vault n=0 rc=0 pid
  local pids=()

  vaults=$(pass-cli vault list --output json | jq -r '.vaults[].name')
  [ -n "$vaults" ] || die "No vaults found."

  # Listing a vault costs a network round trip of a few seconds regardless of
  # its size, so the vaults are fetched concurrently rather than in sequence.
  # The partial listings live under the cache directory rather than in /tmp:
  # they carry item titles, and this way one mode keeps them private.
  SCRATCH=$(mktemp -d "$CACHE_DIR/build.XXXXXX")

  while IFS= read -r vault; do
    n=$((n + 1))
    (
      pass-cli item list "--vault-name=$vault" --filter-state=active \
        --sort-by=alphabetic-asc --output json |
        jq --arg vault "$vault" \
          '[.items[] | {vault: $vault, id, share_id, title, item_type}]'
    ) >"$SCRATCH/$n.json" &
    pids+=($!)
  done <<<"$vaults"

  # A half-fetched index would silently hide items, so one failed vault has to
  # fail the whole rebuild and leave the previous cache in place. Bare `wait`
  # reports success no matter how the jobs ended, hence waiting per pid.
  for pid in "${pids[@]}"; do
    wait "$pid" || rc=1
  done
  [ "$rc" -eq 0 ] || die "Could not list all vaults."

  jq -s 'add' "$SCRATCH"/*.json
  rm -rf "$SCRATCH"
  SCRATCH=""
}

# $1 is "nonblock" for the background refresh, which steps aside if a rebuild
# is already running; "force" for a refresh the user explicitly asked for; and
# empty for a caller that needs a usable cache and waits its turn.
refresh_index() {
  local mode="${1-}" age

  mkdir -p "$CACHE_DIR"
  chmod 700 "$CACHE_DIR"

  # Only one rebuild at a time: two launcher presses in a row must not start
  # competing sets of network calls.
  exec 9>"$CACHE_DIR/lock"
  if [ "$mode" = "nonblock" ]; then
    flock -n 9 || return 0
  else
    flock 9
    # Whoever held the lock may have just built exactly what we were waiting
    # for. An explicitly requested refresh rebuilds regardless.
    age=$(cache_age)
    if [ "$mode" != "force" ] && [ "$age" -ge 0 ] && [ "$age" -lt "$CACHE_TTL" ]; then
      return 0
    fi
  fi

  require_session

  # Holding the lock means no other rebuild is in flight, so anything left
  # behind by an interrupted one is now junk.
  rm -rf "${CACHE_DIR:?}"/build.*

  build_index >"$CACHE_FILE.tmp"
  chmod 600 "$CACHE_FILE.tmp"
  mv "$CACHE_FILE.tmp" "$CACHE_FILE"
}

cache_age() {
  if [ -s "$CACHE_FILE" ]; then
    echo $(($(date +%s) - $(stat -c %Y "$CACHE_FILE")))
  else
    echo -1
  fi
}

load_index() {
  local age
  age=$(cache_age)

  # Waiting for the network before drawing the menu is the whole delay, so a
  # cache that exists is always good enough to open with, however old. A stale
  # one is handed over as-is and replaced in the background, which the next
  # press picks up. Only a first run has nothing to show and has to wait.
  if [ "$age" -ge 0 ] && [ "${1-}" != "force" ]; then
    cat "$CACHE_FILE"
    if [ "$age" -ge "$CACHE_TTL" ]; then
      # Re-run through $BASH rather than executing $0: sourced as a plain file
      # the script has no shebang, and setsid would have nothing to exec.
      setsid "$BASH" "$0" --refresh-cache >/dev/null 2>&1 &
      disown 2>/dev/null || true
    fi
    return
  fi

  [ "$age" -ge 0 ] || notify "Building item index" "First run, this takes a moment"
  refresh_index "${1-}"
  cat "$CACHE_FILE"
}

# Reduce one item to a JSON array of {label, value, totp_field} entries. Values
# stay inside JSON rather than becoming menu lines because notes are routinely
# multi-line and would otherwise spill into the menu as bogus fields.
#
# TOTP entries carry no value: the stored data is a URI, and the code has to be
# generated at the moment it is copied, or it may already have expired.
field_json() {
  jq -c '
    def nonempty: map(select((.value | type) == "string" and .value != ""));

    .item.content as $c
    | ($c.content | to_entries[0].value) as $body
    | [ $c.extra_fields[]? ] as $extra

    | (if ($body.totp_uri // "") != ""
       then [ { label: "TOTP code", totp_field: "totp_uri" } ] else [] end)

    + [ $extra[] | select((.content | keys[0]) == "Totp")
        | { label: ("TOTP: " + .name), totp_field: .name } ]

    + ([ ["Password",    $body.password],
         ["Username",    $body.username],
         ["Email",       $body.email],
         ["Card number", $body.number],
         ["URL",         $body.urls[0]?],
         ["Note",        $c.note]
       ] | map({ label: .[0], value: .[1] }) | nonempty)

    + ([ $extra[] | select((.content | keys[0]) == "Text")
         | { label: .name, value: (.content | to_entries[0].value) } ] | nonempty)

    | map(if (.value // "") | test("\n")
          then .label = "\(.label)  (\(.value | split("\n") | length) lines)"
          else . end)
  '
}

copy() {
  # Value on stdin, never argv. The delayed clear only fires if the clipboard
  # still holds this value, so it will not wipe something copied later.
  local value
  value=$(cat)
  printf '%s' "$value" | wl-copy --type text/plain

  (
    sleep "$CLEAR_AFTER"
    if [ "$(wl-paste --no-newline 2>/dev/null)" = "$value" ]; then
      wl-copy --clear
    fi
  ) >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

main() {
  local index choice line share_id item_id title label value item fields field_index totp_field
  local force="${1-}"

  # Picking refresh re-enters the item menu with a freshly built index rather
  # than recursing, so repeated refreshes cannot stack up.
  while :; do
    index=$(load_index "$force")
    choice=$(
      {
        printf '%s\n' "$REFRESH_ENTRY"
        jq -r '.[] | "\(.vault)/\(.title)  --  \(.item_type)"' <<<"$index"
      } | menu "Proton Pass"
    )
    [ -n "$choice" ] || exit 0
    [ "$choice" = "$REFRESH_ENTRY" ] || break
    notify "Refreshing item list"
    force=force
  done

  # Map the displayed label back to its IDs.
  title=${choice%%"  --  "*}
  line=$(jq -r --arg t "$title" \
    '.[] | select("\(.vault)/\(.title)" == $t) | "\(.share_id)\t\(.id)"' <<<"$index" | head -1)
  [ -n "$line" ] || die "Item not found: $title"
  share_id=${line%%$'\t'*}
  item_id=${line##*$'\t'}

  # Checked only once something has to go over the network. Doing it up front
  # would put a round trip in front of every menu, including the ones served
  # entirely from cache.
  item=$(pass-cli item view "--share-id=$share_id" "--item-id=$item_id" --output json) || {
    require_session
    die "Could not read item: $title"
  }
  fields=$(field_json <<<"$item")
  [ "$(jq length <<<"$fields")" -gt 0 ] || die "No copyable fields on: $title"

  # Entries are numbered because field labels are not unique - imported items
  # routinely carry several fields all named "Text" - and the number is what
  # maps the choice back to the value.
  choice=$(jq -r 'to_entries[] | "\(.key + 1). \(.value.label)"' <<<"$fields" | menu "$title")
  [ -n "$choice" ] || exit 0
  field_index=$((${choice%%.*} - 1))
  label=$(jq -r --argjson i "$field_index" '.[$i].label' <<<"$fields")
  totp_field=$(jq -r --argjson i "$field_index" '.[$i].totp_field // ""' <<<"$fields")

  if [ -n "$totp_field" ]; then
    value=$(pass-cli item totp "--share-id=$share_id" "--item-id=$item_id" \
      "--field=$totp_field" --output json | jq -r 'to_entries[0].value') ||
      die "Could not generate TOTP for: $title"
  else
    value=$(jq -r --argjson i "$field_index" '.[$i].value' <<<"$fields")
  fi

  printf '%s' "$value" | copy
  notify "Copied $label" "$title - clipboard clears in ${CLEAR_AFTER}s"
}

# --refresh-cache is how the script re-invokes itself for a background rebuild,
# and is also what a timer or a shell alias would call to warm the cache.
if [ "${1-}" = "--refresh-cache" ]; then
  refresh_index nonblock
else
  main "${1-}"
fi
