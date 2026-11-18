# Claude Code status line: the caveman badge plus the context size, styled
# at the warning and strong points. Contract:
# specs/007-context-hygiene/contracts/statusline.md. Tested by
# tests/context-statusline.nix.
#
# With usageTap, it also saves the input's rate limits for the Mango rail
# (specs/013-mango-islands-shell/contracts/usage-record.md).
{
  lib,
  writeShellApplication,
  jq,
  coreutils,
  gnugrep,
  gnused,
  bash,
  warnTokens,
  strongTokens,
  # The upstream caveman-statusline.sh, or null when caveman is disabled.
  cavemanScript ? null,
  usageTap ? false,
}:

writeShellApplication {
  name = "context-statusline";
  # The upstream caveman script calls grep, sed, head and tr.
  runtimeInputs = [
    jq
    coreutils
    gnugrep
    gnused
    bash
  ];
  # errexit, nounset and pipefail are on, so every command that can fail is
  # guarded: a status line that errors shows nothing at all.
  text = ''
    input=$(cat || true)

    badge=""
    ${
      if cavemanScript == null then
        ""
      else
        ''
          badge=$(bash ${cavemanScript} <<<"$input" || true)
        ''
    }
    # Missing, null, non-number and 0 are all "no data". `x.yM` is truncated,
    # not rounded, so 1250000 is 1.2M. Comparisons are strict: exactly
    # warnTokens is still neutral.
    size=$(jq -r \
      --argjson warn ${toString warnTokens} \
      --argjson strong ${toString strongTokens} '
      (try .context_window.total_input_tokens catch null) as $t
      | if ($t | type) == "number" and $t > 0 then
          (if $t >= 1000000 then
             ($t / 100000 | floor) as $d | "\($d / 10 | floor).\($d % 10)M"
           else
             "\($t / 1000 | round)K"
           end) as $text
          | (if $t > $strong then "1;37;41"
             elif $t > $warn then "33"
             else "2" end) as $sgr
          | "\u001b[\($sgr)m\($text)\u001b[0m"
        else empty end
    ' <<<"$input" 2>/dev/null || true)

    ${lib.optionalString usageTap ''
      # Rate limits for the Mango rail. Absent for API-key use and before the
      # first response; each window may be missing. Any failure is ignored,
      # so the status line itself never changes.
      (
        record=$(jq -c --argjson now "$(date +%s)" '
          def window: if type == "object" then {used_percentage, resets_at} else null end;
          (try .rate_limits catch null) as $r
          | if ($r | type) == "object" and ($r.five_hour != null or $r.seven_day != null) then
              {updated_at: $now, session: ($r.five_hour | window), weekly: ($r.seven_day | window)}
            else empty end
        ' <<<"$input" 2>/dev/null) || exit 0
        [[ -n $record ]] || exit 0
        dir="''${XDG_STATE_HOME:-$HOME/.local/state}/agent-usage"
        mkdir -p "$dir" || exit 0
        tmp=$(mktemp "$dir/.limits.XXXXXX") || exit 0
        if printf '%s\n' "$record" >"$tmp"; then
          mv -f "$tmp" "$dir/limits.json" || rm -f "$tmp"
        else
          rm -f "$tmp"
        fi
      ) 2>/dev/null || true
    ''}
    sep=""
    if [[ -n $badge && -n $size ]]; then
      sep=" "
    fi
    printf '%s%s%s' "$badge" "$sep" "$size"
    exit 0
  '';
}
