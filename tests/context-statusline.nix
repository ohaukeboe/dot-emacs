# Byte-for-byte tests for workstation/agents/packages/context-statusline.nix,
# run by `nix flake check`. Contract:
# specs/007-context-hygiene/contracts/statusline.md.
#
# Each case pipes a status-line payload in and compares stdout and the exit
# code. The badge comes from the real upstream caveman script, reading a
# `full` mode flag from a throwaway HOME.
{
  runCommand,
  callPackage,
  writeShellScript,
  caveman-src,
}:

let
  build =
    cavemanScript:
    callPackage ../workstation/agents/packages/context-statusline.nix {
      warnTokens = 200000;
      strongTokens = 400000;
      inherit cavemanScript;
    };

  withBadge = build "${caveman-src}/src/hooks/caveman-statusline.sh";
  noBadge = build null;
  failingBadge = build (writeShellScript "failing-badge" "exit 1");
in
runCommand "context-statusline-test" { } ''
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME/.claude"
  printf 'full' > "$HOME/.claude/.caveman-active"

  esc=$(printf '\033')
  badge="$esc[38;5;172m[CAVEMAN]$esc[0m"
  dim() { printf '%s' "$esc[2m$1$esc[0m"; }
  yellow() { printf '%s' "$esc[33m$1$esc[0m"; }
  strong() { printf '%s' "$esc[1;37;41m$1$esc[0m"; }
  tokens() { printf '{"context_window":{"total_input_tokens":%s}}' "$1"; }

  failures=0
  # check NAME EXE INPUT EXPECTED
  check() {
    local actual rc=0
    actual=$(printf '%s' "$3" | "$2"; echo x) || rc=$?
    actual=''${actual%x}
    if [ "$rc" -ne 0 ] || [ "$actual" != "$4" ]; then
      echo "FAIL $1: exit $rc"
      printf '  expected: %q\n  actual:   %q\n' "$4" "$actual"
      failures=$((failures + 1))
    else
      echo "ok   $1"
    fi
  }

  sl=${withBadge}/bin/context-statusline
  check "empty object"  "$sl" '{}'                   "$badge"
  check "null"          "$sl" 'null'                 "$badge"
  check "zero"          "$sl" "$(tokens 0)"          "$badge"
  check "garbage"       "$sl" 'garbage'              "$badge"
  check "38211 dim"     "$sl" "$(tokens 38211)"      "$badge $(dim 38K)"
  check "200000 dim"    "$sl" "$(tokens 200000)"     "$badge $(dim 200K)"
  check "200001 yellow" "$sl" "$(tokens 200001)"     "$badge $(yellow 200K)"
  check "412000 strong" "$sl" "$(tokens 412000)"     "$badge $(strong 412K)"
  check "1250000 1.2M"  "$sl" "$(tokens 1250000)"    "$badge $(strong 1.2M)"
  check "1000000 1.0M"  "$sl" "$(tokens 1000000)"    "$badge $(strong 1.0M)"

  check "no caveman"    ${noBadge}/bin/context-statusline      "$(tokens 38211)" "$(dim 38K)"
  check "failing badge" ${failingBadge}/bin/context-statusline "$(tokens 38211)" "$(dim 38K)"

  [ "$failures" -eq 0 ] || { echo "$failures case(s) failed"; exit 1; }
  touch "$out"
''
