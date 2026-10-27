# rtk's "No hook installed" banner against a HOME shaped like an agent's.
#
#   nix build .#checks.x86_64-linux.rtk-banner -L
#
# workstation/agents/rtk.nix sets RTK_SUPPRESS_HOOK_WARNING because rtk only
# recognises a literal `rtk hook claude` PreToolUse command, while here it runs
# as a stage of agent-bash-rewriter-chain, and the sandbox's read-only
# ~/.local/share stops rtk recording (in rtk/.hook_warn_last) that it already
# warned today. So the banner would land in every shell result.
#
# Two assertions:
#   - Canary: without the variable rtk still warns, twice in a row. If a
#     future rtk drops or renames the warning path, this fails and the
#     suppression in rtk.nix needs a fresh look.
#   - Suppression: with the variable stderr is empty and `rtk ls` still
#     prints, so output compression stays on.
#
# rtk is unfree (BUSL-1.1), so flake.nix passes it in from a nixpkgs that
# carries the repo's unfree predicate.
{
  runCommand,
  rtk,
}:

runCommand "rtk-banner" { nativeBuildInputs = [ rtk ]; } ''
  home="$PWD/home"
  mkdir -p "$home/.claude" "$home/.local/share" "$home/.config" work
  echo hello > work/file.txt

  # One PreToolUse hook that is not `rtk hook claude`, like the rewriter chain.
  cat > "$home/.claude/settings.json" <<'EOF'
  {"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"true"}]}]}}
  EOF
  # Read-only, as in the agent sandbox, so the daily rate limit cannot stamp.
  chmod a-w "$home/.local/share"

  export HOME="$home" XDG_DATA_HOME="$home/.local/share" XDG_CONFIG_HOME="$home/.config"
  unset RTK_SUPPRESS_HOOK_WARNING
  cd work

  for run in 1 2; do
    rtk ls . > ../out 2> ../err
    if [ ! -s ../err ]; then
      echo "tests/rtk-banner.nix: canary run $run without RTK_SUPPRESS_HOOK_WARNING printed no warning;"
      echo "rtk's hook-warning path changed, re-check the suppression in workstation/agents/rtk.nix"
      exit 1
    fi
  done

  RTK_SUPPRESS_HOOK_WARNING=1 rtk ls . > ../out 2> ../err
  if [ -s ../err ]; then
    echo "tests/rtk-banner.nix: RTK_SUPPRESS_HOOK_WARNING=1 left stderr non-empty:"
    cat ../err
    echo "rtk ignores the switch; fix the suppression in workstation/agents/rtk.nix"
    exit 1
  fi
  if [ ! -s ../out ]; then
    echo "tests/rtk-banner.nix: with RTK_SUPPRESS_HOOK_WARNING=1, rtk ls printed nothing;"
    echo "the switch must not disable output, check workstation/agents/rtk.nix"
    exit 1
  fi

  touch "$out"
''
