# game-bench-wrap: Steam launch option `game-bench-wrap %command%`.
#
# Outside a game-bench session it execs the game unchanged. During a session
# it applies the current run's settings from $XDG_RUNTIME_DIR/game-bench/run.env.
# Contract: specs/008-game-performance-tuning/contracts/game-bench-wrap.md.
#
# A session is live only while the PID in `lock` is alive, so a run.env left
# by a crashed session never reaches a normal launch. Steam's FHS env shares
# the host PID namespace (buildFHSEnv unsharePid defaults to false).

dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/game-bench"

live=0
if [ -r "$dir/lock" ] && [ -r "$dir/run.env" ]; then
  pid=$(cat "$dir/lock")
  if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    live=1
  fi
fi
[ "$live" = 1 ] || exec "$@"

prefix=()
# Parsed line by line, never sourced: only these keys take effect.
while IFS= read -r line || [ -n "$line" ]; do
  key=${line%%=*}
  value=${line#*=}
  case "$key" in
  GB_ENV)
    name=${value%%=*}
    if [[ $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then export "$name=${value#*=}"; fi
    ;;
  GB_CPUS)
    if [[ $value =~ ^[0-9,-]+$ ]]; then prefix+=(taskset -c "$value"); fi
    ;;
  GB_GAMEMODE)
    if [ "$value" = 1 ]; then prefix+=(gamemoderun); fi
    ;;
  GB_MANGOHUD)
    export MANGOHUD=1 MANGOHUD_CONFIG="$value"
    ;;
  esac
done <"$dir/run.env"

exec "${prefix[@]}" "$@"
