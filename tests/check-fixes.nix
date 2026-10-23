# Tests for the check-fixes app (scripts/check-fixes.sh), run by
# `nix flake check`:
#
#   nix build .#checks.x86_64-linux.check-fixes -L
#
# The checker talks to the GitHub REST API at $GITHUB_API_URL. Here that is a
# file:// tree laid out as API paths, so the build needs no network. The repo
# it scans is a throwaway git repository built inside the derivation, as in
# tests/beads.nix. The tests assert on the printed report and the exit code
# only.
{
  runCommand,
  git,
  check-fixes,
}:

runCommand "test-check-fixes"
  {
    nativeBuildInputs = [
      git
      check-fixes
    ];
  }
  ''
    export HOME="$PWD/home"
    mkdir -p "$HOME"
    git config --global init.defaultBranch main
    git config --global user.email "test@example.com"
    git config --global user.name "Test"

    pinned=1111111111111111111111111111111111111111
    fixInPin=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    fixUpstream=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

    # --- API fixtures ---------------------------------------------------
    api="$PWD/api"
    repo_api="$api/repos/NixOS/nixpkgs"
    mkdir -p "$repo_api/issues" "$repo_api/pulls" "$repo_api/compare"

    # A merged PR whose merge commit is in the pin.
    echo '{"number":100,"state":"closed","pull_request":{}}' >"$repo_api/issues/100"
    echo '{"number":100,"state":"closed","merged":true,"merge_commit_sha":"'$fixInPin'"}' >"$repo_api/pulls/100"
    echo '{"status":"ahead"}' >"$repo_api/compare/$fixInPin...$pinned"

    # A merged PR whose merge commit is in nixos-unstable only.
    echo '{"number":200,"state":"closed","pull_request":{}}' >"$repo_api/issues/200"
    echo '{"number":200,"state":"closed","merged":true,"merge_commit_sha":"'$fixUpstream'"}' >"$repo_api/pulls/200"
    echo '{"status":"behind"}' >"$repo_api/compare/$fixUpstream...$pinned"
    echo '{"status":"ahead"}' >"$repo_api/compare/$fixUpstream...nixos-unstable"

    # An open PR.
    echo '{"number":300,"state":"open","pull_request":{}}' >"$repo_api/issues/300"
    echo '{"number":300,"state":"open","merged":false,"merge_commit_sha":"cccccccccccccccccccccccccccccccccccccccc"}' >"$repo_api/pulls/300"

    # A PR closed without merging.
    echo '{"number":400,"state":"closed","pull_request":{}}' >"$repo_api/issues/400"
    echo '{"number":400,"state":"closed","merged":false,"merge_commit_sha":"dddddddddddddddddddddddddddddddddddddddd"}' >"$repo_api/pulls/400"

    # An issue closed by a commit, which is the pinned commit itself. The
    # issue's events live where its events_url says, as on GitHub.
    mkdir -p "$api/issue-events"
    echo '{"number":500,"state":"closed","events_url":"file://'$api'/issue-events/500"}' >"$repo_api/issues/500"
    echo '[{"event":"labeled","commit_id":null},{"event":"closed","commit_id":"'$pinned'"}]' >"$api/issue-events/500"
    echo '{"status":"identical"}' >"$repo_api/compare/$pinned...$pinned"

    # An issue closed by hand, with no linked commit.
    echo '{"number":600,"state":"closed","events_url":"file://'$api'/issue-events/600"}' >"$repo_api/issues/600"
    echo '[{"event":"closed","commit_id":null}]' >"$api/issue-events/600"

    # An open issue.
    echo '{"number":700,"state":"open","events_url":"file://'$api'/issue-events/700"}' >"$repo_api/issues/700"

    # --- The repo under check -------------------------------------------
    mkdir repo
    cd repo
    git init -q
    cat >flake.lock <<LOCK
    {"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs_2"}},
              "nixpkgs_2":{"locked":{"rev":"$pinned"}}},
     "root":"root","version":7}
    LOCK
    cat >flake.nix <<'NIX'
    {
      # fixedBy: NixOS/nixpkgs#100
      # fixedBy: NixOS/nixpkgs#300
      # fixedBy: NixOS/nixpkgs#400
      # fixedBy: NixOS/nixpkgs#500
      # fixedBy: NixOS/nixpkgs#600
      # fixedBy: NixOS/nixpkgs#700
    }
    NIX
    mkdir pkgs
    cat >pkgs/a.nix <<'NIX'
    final: prev: {
      foo = final.expiringOverride {
        pkg = prev.foo;
        fixedBy = "NixOS/nixpkgs#200";
        reason = "test";
      } (p: p);
    }
    NIX
    # The same reference as pkgs/a.nix, and a malformed one (no owner).
    cat >pkgs/b.nix <<'NIX'
    # fixedBy: NixOS/nixpkgs#200
    # fixedBy: nixpkgs#123
    { }
    NIX
    # Fixtures under tests/ are not workarounds; #999 has no API fixture, so
    # reading it would also fail the run.
    mkdir tests
    echo '{ fixedBy = "NixOS/nixpkgs#999"; }' >tests/fixture.nix
    git add -A

    # --- Run ------------------------------------------------------------
    status=0
    GITHUB_API_URL="file://$api" check-fixes >"$TMPDIR/report" 2>&1 || status=$?
    cat "$TMPDIR/report"

    fail() {
      echo "FAIL: $*"
      exit 1
    }
    expect_line() {
      grep -qFx -- "$1" "$TMPDIR/report" || fail "missing line: $1"
    }

    [ "$status" -eq 0 ] || fail "exit code $status, expected 0"
    expect_line "pinned-fixed NixOS/nixpkgs#100 (flake.nix:2): fix is in the pinned nixpkgs, remove the workaround"
    expect_line "upstream-fixed NixOS/nixpkgs#200 (pkgs/a.nix:4, pkgs/b.nix:1): fix is in nixos-unstable but not the pin, run nix flake update"
    expect_line "pending NixOS/nixpkgs#300 (flake.nix:3): still open"
    expect_line "closed-unmerged NixOS/nixpkgs#400 (flake.nix:4): closed without merging, find the replacement PR"
    expect_line "pinned-fixed NixOS/nixpkgs#500 (flake.nix:5): fix is in the pinned nixpkgs, remove the workaround"
    expect_line "unknown NixOS/nixpkgs#600 (flake.nix:6): closed, fix commit unknown, point me at the PR"
    expect_line "pending NixOS/nixpkgs#700 (flake.nix:7): still open"
    [ "$(grep -c 'NixOS/nixpkgs#200' "$TMPDIR/report")" -eq 1 ] || fail "#200 reported more than once"
    expect_line "warning: pkgs/b.nix:2: cannot parse fix reference: # fixedBy: nixpkgs#123"
    ! grep -q '#999' "$TMPDIR/report" || fail "reported a reference under tests/"

    # An API that cannot be read is an error, not a report.
    status=0
    GITHUB_API_URL="file://$PWD/nowhere" check-fixes >"$TMPDIR/report" 2>&1 || status=$?
    cat "$TMPDIR/report"
    [ "$status" -ne 0 ] || fail "exit code 0 with an unreachable API"

    # A PR response without a boolean "merged" is an API error, not a PR
    # closed without merging. Checked in a repo of its own, since the run
    # above must exit 0.
    echo '{"number":800,"state":"closed","pull_request":{}}' >"$repo_api/issues/800"
    echo '{"message":"Server Error"}' >"$repo_api/pulls/800"
    cd ..
    mkdir repo-bad-pr
    cd repo-bad-pr
    git init -q
    cp ../repo/flake.lock .
    echo '{ } # fixedBy: NixOS/nixpkgs#800' >flake.nix
    git add -A
    status=0
    GITHUB_API_URL="file://$api" check-fixes >"$TMPDIR/report" 2>&1 || status=$?
    cat "$TMPDIR/report"
    [ "$status" -ne 0 ] || fail "exit code 0 with a malformed PR response"
    ! grep -q '^closed-unmerged' "$TMPDIR/report" || fail "malformed PR response reported as closed-unmerged"

    touch "$out"
  ''
