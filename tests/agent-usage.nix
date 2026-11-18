# Fixture tests for workstation/agents/packages/agent-usage-tokens.py, run by
# `nix flake check`. Contract:
# specs/013-mango-islands-shell/contracts/usage-record.md.
#
# The transcripts hold a streamed message written twice, two models, a
# message from outside the 7-day window, a subagent transcript and a
# malformed line.
{
  runCommand,
  callPackage,
  jq,
}:

let
  collector = callPackage ../workstation/agents/packages/agent-usage-tokens.nix { };
in
runCommand "agent-usage-test" { } ''
  export TZ=UTC
  export HOME="$TMPDIR/home"
  export XDG_STATE_HOME="$TMPDIR/state"
  projects="$HOME/.claude/projects/-proj"
  mkdir -p "$projects/session/subagents"

  today=$(date -u +%Y-%m-%d)
  yesterday=$(date -u -d yesterday +%Y-%m-%d)
  old=$(date -u -d '10 days ago' +%Y-%m-%d)
  msg() { # id request model day input output cache-create cache-read
    printf '{"type":"assistant","requestId":"%s","timestamp":"%sT10:00:00.000Z","message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}\n' \
      "$2" "$4" "$1" "$3" "$5" "$6" "$7" "$8"
  }
  {
    msg m1 r1 opus "$today" 10 20 30 40
    msg m1 r1 opus "$today" 10 20 30 40
    msg m2 r2 sonnet "$yesterday" 1 2 3 4
    msg m3 r3 opus "$old" 1000 0 0 0
    echo 'not json'
    echo '{"type":"user","message":{"content":"hi"}}'
  } > "$projects/session.jsonl"
  msg m4 r4 sonnet "$today" 100 0 0 0 > "$projects/session/subagents/agent-a.jsonl"

  # No credentials: no limits.json, tokens still counted.
  ${collector}/bin/agent-usage-tokens
  limits_json="$XDG_STATE_HOME/agent-usage/limits.json"
  if [ -e "$limits_json" ]; then echo "FAIL limits.json without credentials"; exit 1; fi

  # Credentials and a canned endpoint response.
  printf '{"claudeAiOauth":{"accessToken":"t","expiresAt":%s000}}' "$(($(date +%s) + 3600))" \
    > "$HOME/.claude/.credentials.json"
  echo '{"five_hour":{"utilization":20.4,"resets_at":"2026-11-14T21:00:00.5+00:00"},"seven_day":{"utilization":3.0,"resets_at":null}}' \
    > "$TMPDIR/usage.json"
  AGENT_USAGE_URL="file://$TMPDIR/usage.json" ${collector}/bin/agent-usage-tokens
  cat "$limits_json"
  ${jq}/bin/jq -e '.session == {used_percentage: 20, resets_at: 1794690000}
    and .weekly == {used_percentage: 3, resets_at: null} and (.updated_at | type) == "number"' \
    "$limits_json" >/dev/null || { echo "FAIL limits.json"; exit 1; }
  echo "ok   limits from endpoint"

  out_json="$XDG_STATE_HOME/agent-usage/tokens.json"
  cat "$out_json"

  failures=0
  expect() { # NAME JQ-FILTER
    if ${jq}/bin/jq -e "$2" "$out_json" >/dev/null; then
      echo "ok   $1"
    else
      echo "FAIL $1"
      failures=$((failures + 1))
    fi
  }
  expect "seven days"        '.days | length == 7'
  expect "today last"        ".days[-1] == {date: \"$today\", tokens: 200}"
  expect "yesterday"         ".days[-2] == {date: \"$yesterday\", tokens: 10}"
  expect "old day dropped"   '[.days[].tokens] | add == 210'
  expect "week total"        '.week_tokens == 210'
  expect "models by tokens"  '.models == [{model: "sonnet", tokens: 110}, {model: "opus", tokens: 100}]'
  expect "no error"          'has("error") | not'

  [ "$failures" -eq 0 ] || { echo "$failures case(s) failed"; exit 1; }
  touch "$out"
''
