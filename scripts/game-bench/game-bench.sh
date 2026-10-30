# game-bench: unattended game benchmark sessions.
#
#   game-bench run [-w WORKLOAD] [-v "V1 V2 ..."] [-n RUNS] [--load] [--cool SECS]
#   game-bench compare SESSION_DIR SESSION_DIR [...]
#   game-bench build-time [-n RUNS]
#   game-bench restore
#   game-bench list
#
# Contract: specs/008-game-performance-tuning/contracts/game-bench-cli.md.
# Records: specs/008-game-performance-tuning/data-model.md.
#
# runtimeEnv (modules/gaming/bench/packages.nix):
#   GAME_BENCH_CONFIG         JSON {variants, workloads} from the Nix options
#   GAME_BENCH_PRIV           store path of game-bench-priv (the sudo rule names it)
#   GAME_BENCH_SUMMARY        game-bench-summary
#   GAME_BENCH_STEAM          the Steam launcher
#   GAME_BENCH_FACTORIO_SAVE  pinned benchmark save
#   GAME_BENCH_LOAD_DRV       derivation rebuilt as background load
#   GAME_BENCH_VERSIONS       JSON file of versions known at build time

data="${XDG_DATA_HOME:-$HOME/.local/share}/game-bench"
rt="${XDG_RUNTIME_DIR:?game-bench needs XDG_RUNTIME_DIR}/game-bench"
lock="$rt/lock"
journal="$rt/journal"
session_journal="$rt/session-journal"
runenv="$rt/run.env"
steam_root="$HOME/.local/share/Steam"

say() { echo "game-bench: $*" >&2; }
die() {
  say "$*"
  exit 2
}

cfg() { jq -r "$@" "$GAME_BENCH_CONFIG"; }

priv() { sudo -n "$GAME_BENCH_PRIV" "$@"; }

# ---------------------------------------------------------------- journal

# Record how to undo a change before making it (FR-005).
# Fields are tab-separated: paths in a Proton prefix contain spaces.
# Run-level undos ($journal) are replayed after every run; session-level
# ones ($session_journal, the settings swap) when the session ends.
journal_add() {
  local IFS=$'\t'
  printf '%s\n' "$*" >>"$journal"
}

session_journal_add() {
  local IFS=$'\t'
  printf '%s\n' "$*" >>"$session_journal"
}

replay_journal() {
  local journal=${1:-$journal}
  [ -s "$journal" ] || return 0
  local line op a b
  while IFS= read -r line; do
    IFS=$'\t' read -r op a b <<<"$line"
    case "$op" in
    priv) priv "$a" ${b:+"$b"} || say "restore failed: priv $a $b" ;;
    ppd) powerprofilesctl set "$a" || say "restore failed: ppd $a" ;;
    file) mv -f "$a" "$b" || say "restore failed: file $a -> $b" ;;
    esac
  done < <(tac "$journal")
  : >"$journal"
}

replay_all() {
  replay_journal "$journal"
  replay_journal "$session_journal"
}

# ---------------------------------------------------------------- lock

session_live() {
  [ -r "$lock" ] || return 1
  local pid
  pid=$(cat "$lock")
  [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

take_lock() {
  mkdir -p "$rt"
  if session_live; then
    die "another session (PID $(cat "$lock")) is running"
  fi
  if [ -s "$journal" ] || [ -s "$session_journal" ]; then
    say "restoring settings left by a session that did not finish"
    replay_all
  fi
  rm -f "$runenv"
  echo $$ >"$lock"
}

# ---------------------------------------------------------------- steam

library_dirs() {
  echo "$steam_root"
  local vdf="$steam_root/steamapps/libraryfolders.vdf"
  if [ -r "$vdf" ]; then sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"/\1/p' "$vdf"; fi
}

# First existing path below a Steam library, or nothing.
in_library() {
  local lib
  while IFS= read -r lib; do
    if [ -e "$lib/$1" ]; then
      echo "$lib/$1"
      return 0
    fi
  done < <(library_dirs)
  return 1
}

game_build() {
  local acf
  acf=$(in_library "steamapps/appmanifest_$1.acf") || {
    echo unknown
    return
  }
  sed -n 's/^[[:space:]]*"buildid"[[:space:]]*"\([0-9]*\)".*/\1/p' "$acf" | head -n1
}

# Compatibility tool configured for the app, or the global default ("0").
compat_tool() {
  local vdf="$steam_root/config/config.vdf" tool
  [ -r "$vdf" ] || {
    echo unknown
    return
  }
  tool=$(awk -v app="\"$1\"" '
    /"CompatToolMapping"/ { inmap = 1 }
    inmap && $1 == app { inapp = 1 }
    inapp && $1 == "\"name\"" { gsub(/"/, "", $2); print $2; exit }
  ' "$vdf")
  if [ -z "$tool" ]; then
    tool=$(awk '
      /"CompatToolMapping"/ { inmap = 1 }
      inmap && $1 == "\"0\"" { inapp = 1 }
      inapp && $1 == "\"name\"" { gsub(/"/, "", $2); print $2; exit }
    ' "$vdf")
  fi
  echo "${tool:-native}"
}

reaper_pattern() { echo "reaper.*SteamLaunch AppId=$1( |$)"; }

# ---------------------------------------------------------------- state

read_or() { cat "$1" 2>/dev/null || echo "$2"; }

gpu_hwmon() {
  local h
  for h in /sys/class/hwmon/hwmon*; do
    if [ "$(cat "$h/name" 2>/dev/null)" = amdgpu ] && [ -e "$h/power1_cap" ]; then
      echo "$h"
      return 0
    fi
  done
  return 1
}

gpu_od_file() {
  local h
  h=$(gpu_hwmon) || return 1
  echo "$(readlink -f "$h/device")/pp_od_clk_voltage"
}

# The overdrive voltage offset in mV ("0", "-50"); empty with overdrive off.
gpu_voltage_offset() {
  local od
  od=$(gpu_od_file) || return 0
  [ -r "$od" ] || return 0
  sed -n '/^OD_VDDGFX_OFFSET:/{n;s/[^0-9-]//g;p;q}' "$od"
}

snapshot() {
  local h dev cap="" level="" profile="" preempt="" slice=""
  if h=$(gpu_hwmon); then
    dev=$(readlink -f "$h/device")
    cap=$(($(cat "$h/power1_cap") / 1000000))
    level=$(read_or "$dev/power_dpm_force_performance_level" "")
    profile=$(sed -n 's/^ *[0-9]\+ *\([A-Z_0-9]*\) *\*.*/\1/p' "$dev/pp_power_profile_mode" 2>/dev/null | head -n1)
  fi
  if [ -n "${needs_root:-}" ]; then
    preempt=$(priv zen-knobs status 2>/dev/null | sed -n 's/^preempt=//p')
    slice=$(priv zen-knobs status 2>/dev/null | sed -n 's/^base_slice_ns=//p')
  fi
  jq -n \
    --arg kernel "$(uname -r)" \
    --arg bootedSystem "$(readlink /run/booted-system)" \
    --arg schedExt "$(read_or /sys/kernel/sched_ext/state unsupported)" \
    --arg scxOps "$(read_or /sys/kernel/sched_ext/root/ops "")" \
    --arg system76 "$(systemctl is-active system76-scheduler 2>/dev/null || true)" \
    --arg governor "$(read_or /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor "")" \
    --arg epp "$(read_or /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference "")" \
    --arg ppdProfile "$(powerprofilesctl get 2>/dev/null || true)" \
    --arg gpuPerfLevel "$level" \
    --arg gpuProfileMode "$profile" \
    --arg gpuPowerCap "$cap" \
    --arg gpuVoltageOffset "$(gpu_voltage_offset)" \
    --arg preempt "$preempt" \
    --arg baseSlice "$slice" \
    --argjson loadRunning "$([ -n "${load_pid:-}" ] && echo true || echo false)" \
    '$ARGS.named'
}

# Does the "after" snapshot still show the variant in effect?
state_matches() {
  local v=$1 after=$2 want
  want=$(cfg --arg v "$v" '.variants[$v].scx // ""')
  if [ -n "$want" ] && [ "$(jq -r .schedExt <<<"$after")" != enabled ]; then return 1; fi
  if [ -z "$want" ] && [ "$(jq -r .schedExt <<<"$after")" = enabled ]; then return 1; fi
  want=$(cfg --arg v "$v" '.variants[$v].cpuProfile // ""')
  if [ -n "$want" ] && [ "$(jq -r .ppdProfile <<<"$after")" != "$want" ]; then return 1; fi
  if [ "$(cfg --arg v "$v" '.variants[$v].stopSystem76')" = true ] &&
    [ "$(jq -r .system76 <<<"$after")" = active ]; then return 1; fi
  if [ -n "${cap_watts:-}" ] && [ "$(jq -r .gpuPowerCap <<<"$after")" != "$cap_watts" ]; then return 1; fi
  # A driver reset (a too-deep undervolt) clears the offset.
  want=$(cfg --arg v "$v" '.variants[$v].gpuUndervoltMv // "" | tostring')
  if [ -n "$want" ] && [ "$(jq -r .gpuVoltageOffset <<<"$after")" != "-$want" ]; then return 1; fi
  return 0
}

# ---------------------------------------------------------------- variants

variant_needs_root() {
  # cpuProfile is not here: powerprofilesctl works as the user.
  cfg --arg v "$1" '.variants[$v] | .scx != null or .stopSystem76 or .zenKnobs
    or .gpuProfile != null or .gpuPowerCap != null or .gpuUndervoltMv != null'
}

# Running a non-Zen kernel (the default since docs/gaming-benchmarks.md, or
# the comparison entry tagged "stock")?
booted_stock() {
  case "$(uname -r)" in *zen*) return 1 ;; esac
  return 0
}

# Apply a variant's system-wide part; journal each undo first.
apply_variant() {
  local v=$1 value range current offset
  cap_watts=""
  value=$(cfg --arg v "$v" '.variants[$v].cpuProfile // ""')
  if [ -n "$value" ]; then
    journal_add ppd "$(powerprofilesctl get)"
    powerprofilesctl set "$value"
  fi
  if [ "$(cfg --arg v "$v" '.variants[$v].stopSystem76')" = true ]; then
    journal_add priv s76-start
    priv s76-stop
  fi
  value=$(cfg --arg v "$v" '.variants[$v].scx // ""')
  if [ -n "$value" ]; then
    journal_add priv scx-stop
    priv scx-start "$value" || return 1
  fi
  if [ "$(cfg --arg v "$v" '.variants[$v].zenKnobs')" = true ]; then
    journal_add priv zen-knobs off
    priv zen-knobs on || return 1
  fi
  value=$(cfg --arg v "$v" '.variants[$v].gpuProfile // ""')
  if [ -n "$value" ]; then
    journal_add priv gpu-profile default
    priv gpu-profile "$value" || return 1
  fi
  value=$(cfg --arg v "$v" '.variants[$v].gpuPowerCap // "" | tostring')
  if [ -n "$value" ]; then
    read -r -a range <<<"$(priv gpu-cap-range)"
    case "$value" in
    max) cap_watts=${range[2]} ;;
    *%) cap_watts=$((range[1] * ${value%\%} / 100)) ;;
    *) cap_watts=$value ;;
    esac
    # Back to the limit in force (modules.gaming.gpu.powerCapWatts), not stock.
    # The journal replays in reverse: the offset is restored after the cap.
    offset=$(gpu_voltage_offset)
    if [ -n "$offset" ]; then journal_add priv gpu-undervolt "${offset#-}"; fi
    current=$(($(cat "$(gpu_hwmon)/power1_cap") / 1000000))
    journal_add priv gpu-cap "$current"
    priv gpu-cap "$cap_watts" || return 1
    # The SMU rounds the limit: the overdrive maximum, 333 W, reads back 330.
    cap_watts=$(($(cat "$(gpu_hwmon)/power1_cap") / 1000000))
    # Keep the offset in force (modules.gaming.gpu.undervoltMv).
    if [ -n "$offset" ]; then priv gpu-undervolt "${offset#-}" || return 1; fi
  fi
  # After the cap: a cap above the board's own maximum goes to the SMU in
  # the overdrive table, and on 2026-10-30 that left the card running as
  # if the offset were gone (uv-50-300w clocked below uv-50 at 290 W)
  # while pp_od_clk_voltage still showed it.
  value=$(cfg --arg v "$v" '.variants[$v].gpuUndervoltMv // "" | tostring')
  if [ -n "$value" ]; then
    current=$(gpu_voltage_offset)
    journal_add priv gpu-undervolt "${current#-}"
    priv gpu-undervolt "$value" || return 1
  fi
}

# The per-game part, read by game-bench-wrap (never sourced).
write_runenv() {
  local v=$1 mangohud=$2 cpus
  {
    cfg --arg v "$v" '.variants[$v].env | to_entries[] | "GB_ENV=\(.key)=\(.value)"'
    cpus=$(cfg --arg v "$v" '.variants[$v].cpus // ""')
    if [ -n "$cpus" ]; then echo "GB_CPUS=$cpus"; fi
    if [ "$(cfg --arg v "$v" '.variants[$v].gamemode')" = true ]; then echo "GB_GAMEMODE=1"; fi
    if [ -n "$mangohud" ]; then echo "GB_MANGOHUD=$mangohud"; fi
  } >"$runenv"
}

# ---------------------------------------------------------------- runs

# Steam starts a short-lived reaper (runtime setup) before the game's own,
# so the game counts as gone only after `exit_grace` seconds with none.
exit_grace=20
game_gone() {
  local _
  for _ in $(seq "$exit_grace"); do
    if pgrep -f -- "$1" >/dev/null; then return 1; fi
    sleep 1
  done
}

# GPU telemetry once a second until killed, as CSV: board power (µW),
# GFX and memory clocks (Hz), edge, junction and memory temperature (m°C)
# from amdgpu's hwmon, fan speed (RPM) and load (%). Builtin reads only.
sample_gpu() {
  local h dev p sclk mclk edge jct mem fan busy
  h=$(gpu_hwmon) || return 0
  dev=$(readlink -f "$h/device")
  {
    echo "epoch,power_uw,sclk_hz,mclk_hz,edge_mc,junction_mc,mem_mc,fan_rpm,busy_pct"
    while :; do
      read -r p 2>/dev/null <"$h/power1_average" || p=""
      read -r sclk 2>/dev/null <"$h/freq1_input" || sclk=""
      read -r mclk 2>/dev/null <"$h/freq2_input" || mclk=""
      read -r edge 2>/dev/null <"$h/temp1_input" || edge=""
      read -r jct 2>/dev/null <"$h/temp2_input" || jct=""
      read -r mem 2>/dev/null <"$h/temp3_input" || mem=""
      read -r fan 2>/dev/null <"$h/fan1_input" || fan=""
      read -r busy 2>/dev/null <"$dev/gpu_busy_percent" || busy=""
      # EPOCHREALTIME uses the locale's decimal separator.
      printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "${EPOCHREALTIME/,/.}" \
        "$p" "$sclk" "$mclk" "$edge" "$jct" "$mem" "$fan" "$busy"
      sleep 1
    done
  } >"$1"
}

stop_sampler() {
  if [ -n "${sampler_pid:-}" ]; then kill "$sampler_pid" 2>/dev/null || true; fi
  sampler_pid=""
}

# The reaper and everything under it. The game and its Wine processes are
# its descendants; killing the reaper alone leaves a game frozen on a lost
# GPU device running, and Steam then refuses every later launch.
game_tree() {
  local pids next
  pids=$(pgrep -d, -f -- "$(reaper_pattern "$appid")") || return 0
  while [ -n "$pids" ]; do
    tr , '\n' <<<"$pids"
    next=$(pgrep -d, -P "$pids") || break
    pids=$next
  done
}

# Fails when part of the game survives SIGKILL, stuck in the driver.
kill_game() {
  local pids _
  mapfile -t pids < <(game_tree | sort -u)
  [ ${#pids[@]} -gt 0 ] || return 0
  kill "${pids[@]}" 2>/dev/null || true
  sleep 5
  kill -KILL "${pids[@]}" 2>/dev/null || true
  for _ in $(seq 30); do
    kill -0 "${pids[@]}" 2>/dev/null || return 0
    sleep 1
  done
  say "game processes survived SIGKILL: $(ps -o pid=,stat=,comm= -p "${pids[*]}" | tr '\n' ' ')"
  return 1
}

# Did amdgpu log a ring timeout or a GPU reset since epoch $1? A ring
# reset leaves the game frozen on a lost device and it never exits (a
# too-deep undervolt, ADR 0010). grep reads all input: -q would end
# journalctl early, and pipefail would report its SIGPIPE.
gpu_hung() {
  journalctl -k -q -o cat --since "@$1" 2>/dev/null |
    grep -E 'amdgpu .*(ring [^ ]+ timeout|GPU reset begin)' >/dev/null
}

run_proton() {
  local dir=$1 v=$2 pattern started=0 marker since=$EPOCHSECONDS
  pattern=$(reaper_pattern "$appid")
  # Steam refuses to launch over a running instance ("already running").
  if ! game_gone "$pattern"; then
    echo "failed:busy" >"$dir/status"
    return
  fi
  marker="$dir/.start"
  touch "$marker"
  write_runenv "$v" "no_display,autostart_log=$log_delay,log_duration=$log_seconds,log_interval=0,output_folder=$dir"
  "$GAME_BENCH_STEAM" -applaunch "$appid" "${args[@]}" >/dev/null 2>&1 &
  disown || true
  for _ in $(seq 120); do
    if pgrep -f -- "$pattern" >/dev/null; then
      started=1
      break
    fi
    sleep 1
  done
  if [ "$started" = 0 ]; then
    echo "failed:start" >"$dir/status"
    rm -f "$runenv"
    return
  fi
  sample_gpu "$dir/gpu.csv" &
  sampler_pid=$!
  local deadline=$((SECONDS + timeout))
  until game_gone "$pattern"; do
    if gpu_hung "$since"; then
      stop_sampler
      kill_game || game_stuck=1
      echo "failed:gpu-hang" >"$dir/status"
      rm -f "$runenv"
      return
    fi
    if ((SECONDS >= deadline)); then
      stop_sampler
      kill_game || true
      echo "failed:timeout" >"$dir/status"
      rm -f "$runenv"
      return
    fi
    sleep 2
  done
  stop_sampler
  rm -f "$runenv"
  local log
  log=$(find "$dir" -maxdepth 1 -name '*.csv' ! -name '*_summary.csv' ! -name gpu.csv -newer "$marker" -printf '%T@ %p\n' | sort -n | tail -n1 | cut -d' ' -f2-)
  find "$dir" -maxdepth 1 -name '*_summary.csv' -delete
  if [ -n "$log" ]; then mv "$log" "$dir/frames.csv"; fi
  # Cyberpunk writes summary.json and a per-frame frames.csv for exactly
  # the benchmark pass; summary.py prefers that log to MangoHud's.
  local pfx result
  if pfx=$(in_library "steamapps/compatdata/$appid/pfx"); then
    result=$(find "$pfx/drive_c/users/steamuser" -name summary.json -newer "$marker" 2>/dev/null | head -n1)
    if [ -n "$result" ]; then
      cp "$result" "$dir/game.json"
      if [ -e "${result%/*}/frames.csv" ]; then cp -p "${result%/*}/frames.csv" "$dir/game-frames.csv"; fi
    fi
  fi
  if [ ! -e "$dir/frames.csv" ] && [ ! -e "$dir/game-frames.csv" ]; then
    echo "failed:nolog" >"$dir/status"
    return
  fi
  echo valid >"$dir/status"
}

# Register the native game's process with gamemoded once it appears.
# gamemoderun would preload libgamemodeauto into steam-run, bwrap and every
# child; it aborts on exit there, as it did in the Steam client (R7).
# Factorio re-executes itself as bin/x64/../x64_/factorio, so match the
# run's own mod directory; -n picks the game over bwrap and steam-run.
request_gamemode() {
  local mods=$1 log=$2 pid="" _
  for _ in $(seq 50); do
    pid=$(pgrep -n -f -- "/factorio --mod-directory $mods " || true)
    if [ -n "$pid" ]; then break; fi
    sleep 0.2
  done
  if [ -z "$pid" ]; then
    echo "no factorio process for $mods" >"$log"
    return 1
  fi
  gamemoded --request="$pid" >"$log" 2>&1
}

run_native() {
  local dir=$1 v=$2 bin cpus prefix=() work mods save gamemode=0 game rc
  bin=$(in_library "steamapps/common/Factorio/bin/x64/factorio") || {
    echo "failed:start" >"$dir/status"
    return
  }
  cpus=$(cfg --arg v "$v" '.variants[$v].cpus // ""')
  if [ -n "$cpus" ]; then prefix+=(taskset -c "$cpus"); fi
  if [ "$(cfg --arg v "$v" '.variants[$v].gamemode')" = true ]; then gamemode=1; fi
  # Under $HOME, not /tmp: steam-run gives the game a private /tmp.
  work=$(mktemp -d -p "$data" .factorio.XXXXXX)
  # Separate dirs: Factorio loads every zip in --mod-directory as a mod.
  mods="$work/mods"
  save="$work/benchmark.zip"
  mkdir "$mods"
  cp "$GAME_BENCH_FACTORIO_SAVE" "$save"
  chmod u+w "$save"
  local -a env_args=()
  while IFS= read -r kv; do env_args+=("$kv"); done < <(cfg --arg v "$v" '.variants[$v].env | to_entries[] | "\(.key)=\(.value)"')
  env "${env_args[@]}" timeout "$timeout" "${prefix[@]}" steam-run "$bin" \
    --mod-directory "$mods" --disable-audio \
    --benchmark "$save" --benchmark-ticks "$ticks" --benchmark-runs 1 \
    --benchmark-verbose all --benchmark-sanitize >"$dir/factorio.out" 2>&1 &
  game=$!
  local gm_ok=1
  if [ "$gamemode" = 1 ] && ! request_gamemode "$mods" "$dir/gamemode.log"; then gm_ok=0; fi
  if wait "$game"; then rc=0; else rc=$?; fi
  if [ "$rc" -eq 124 ]; then
    echo "failed:timeout" >"$dir/status"
  elif [ "$rc" -ne 0 ]; then
    echo "failed:start" >"$dir/status"
  elif [ "$gm_ok" = 0 ]; then
    echo "failed:gamemode" >"$dir/status"
  else
    echo valid >"$dir/status"
  fi
  rm -rf "$work"
}

one_run() {
  local v=$1 dir=$2 before after
  mkdir -p "$dir"
  before=$(snapshot)
  if ! apply_variant "$v"; then
    echo "excluded:apply" >"$dir/status"
  elif [ "$kind" = native ]; then
    run_native "$dir" "$v"
  else
    run_proton "$dir" "$v"
  fi
  after=$(snapshot)
  jq -n --argjson before "$before" --argjson after "$after" '{$before, $after}' >"$dir/state.json"
  if [ "$(cat "$dir/status")" = valid ] && ! state_matches "$v" "$after"; then
    echo "excluded:state" >"$dir/status"
  fi
  replay_journal
}

# ---------------------------------------------------------------- load

start_load() {
  setsid bash -c '
    while :; do
      nix build --rebuild --no-link --option cores 0 "$1^out" >/dev/null 2>&1 || true
    done' _ "$GAME_BENCH_LOAD_DRV" &
  load_pid=$!
}

stop_load() {
  [ -n "${load_pid:-}" ] || return 0
  kill -- "-$load_pid" 2>/dev/null || kill "$load_pid" 2>/dev/null || true
  load_pid=""
}

# ---------------------------------------------------------------- commands

cleanup() {
  local status=$?
  stop_load
  stop_sampler
  if [ -n "${appid:-}" ] && [ "${kind:-}" = proton ] && pgrep -f -- "$(reaper_pattern "$appid")" >/dev/null; then
    kill_game || true
  fi
  replay_all
  rm -f "$runenv" "$lock"
  exit "$status"
}

cmd_run() {
  local workload=cyberpunk chosen="" runs=5 load=0 cool=60
  while [ $# -gt 0 ]; do
    case "$1" in
    -w)
      workload=$2
      shift 2
      ;;
    -v)
      chosen=$2
      shift 2
      ;;
    -n)
      runs=$2
      shift 2
      ;;
    --load)
      load=1
      shift
      ;;
    --cool)
      cool=$2
      shift 2
      ;;
    *) die "run: unknown argument '$1'" ;;
    esac
  done
  [[ $runs =~ ^[1-9][0-9]*$ ]] || die "run: -n must be a positive number"
  [[ $cool =~ ^[0-9]+$ ]] || die "run: --cool must be a number of seconds"
  [ "$(cfg --arg w "$workload" '.workloads | has($w)')" = true ] || die "unknown workload '$workload' (game-bench list)"

  kind=$(cfg --arg w "$workload" '.workloads[$w].kind')
  appid=$(cfg --arg w "$workload" '.workloads[$w].appid')
  mapfile -t args < <(cfg --arg w "$workload" '.workloads[$w].args[]')
  log_delay=$(cfg --arg w "$workload" '.workloads[$w].logDelay')
  log_seconds=$(cfg --arg w "$workload" '.workloads[$w].logSeconds')
  ticks=$(cfg --arg w "$workload" '.workloads[$w].ticks')
  timeout=$(cfg --arg w "$workload" '.workloads[$w].timeout')

  [ -n "$chosen" ] || chosen=$(cfg '.variants | keys[]' | tr '\n' ' ')
  local v variants=() na=()
  for v in $chosen; do
    [ "$(cfg --arg v "$v" '.variants | has($v)')" = true ] || die "unknown variant '$v' (game-bench list)"
    if [ "$(cfg --arg v "$v" --arg k "$kind" '.variants[$v].workloads | index($k) != null')" != true ] ||
      { [ "$(cfg --arg v "$v" '.variants[$v].zenKnobs')" = true ] && ! booted_stock; } ||
      { [ "$(cfg --arg v "$v" '.variants[$v].gpuUndervoltMv != null')" = true ] &&
        [ -z "$(gpu_voltage_offset)" ]; }; then
      na+=("$v")
    else
      variants+=("$v")
    fi
  done
  [ "${#na[@]}" -eq 0 ] || say "n/a for $workload: ${na[*]}"
  [ "${#variants[@]}" -gt 0 ] || die "no applicable variants"
  [[ " ${variants[*]} " == *" baseline "* ]] || variants=(baseline "${variants[@]}")

  needs_root=""
  for v in "${variants[@]}"; do
    if [ "$(variant_needs_root "$v")" = true ]; then needs_root=1; fi
  done
  if [ -n "$needs_root" ] && ! priv check 2>/dev/null; then
    die "sudo -n $GAME_BENCH_PRIV check failed; is modules.gaming.benchmark.enable deployed?"
  fi

  take_lock
  trap cleanup EXIT
  trap 'exit 130' INT TERM HUP

  local session settings_target=""
  session="$data/$(date +%Y%m%d-%H%M%S)-$workload"
  mkdir -p "$session"
  echo "$session"

  local settings
  settings=$(cfg --arg w "$workload" '.workloads[$w].settingsFile // ""')
  if [ -n "$settings" ]; then
    settings=${settings/#\~/$HOME}
    [ -r "$settings" ] || die "settings file $settings is missing; see quickstart.md step 4"
    local pfx
    pfx=$(in_library "steamapps/compatdata/$appid/pfx") || die "no Proton prefix for app $appid; start the game once"
    settings_target="$pfx/drive_c/users/steamuser/$(cfg --arg w "$workload" '.workloads[$w].settingsTarget')"
    cp -p "$settings_target" "$session/settings.orig"
    session_journal_add file "$session/settings.orig" "$settings_target"
    cp "$settings" "$settings_target"
  fi

  if [ "$load" = 1 ]; then start_load; fi

  jq -n \
    --arg workload "$workload" --arg kind "$kind" \
    --argjson variants "$(printf '%s\n' "${variants[@]}" | jq -R . | jq -s .)" \
    --argjson na "$(printf '%s\n' "${na[@]}" | jq -R 'select(. != "")' | jq -s .)" \
    --argjson runs "$runs" --argjson load "$([ "$load" = 1 ] && echo true || echo false)" \
    --arg start "$(date -Is)" \
    --slurpfile built "$GAME_BENCH_VERSIONS" \
    --arg kernel "$(uname -r)" \
    --arg bootedSystem "$(readlink /run/booted-system)" \
    --arg game "$(game_build "$appid")" \
    --arg compat "$(compat_tool "$appid")" \
    '{workload: $workload, kind: $kind, variants: $variants, na: $na, runs: $runs,
      load: $load, start: $start,
      versions: ($built[0] + {kernel: $kernel, bootedSystem: $bootedSystem,
                           game: $game, compatTool: $compat})}' >"$session/session.json"

  say "warm-up run (discarded)"
  one_run baseline "$session/.warmup"
  rm -rf "$session/.warmup"

  # A variant that hung the GPU once would hang it again; a full reset
  # also ends the desktop session and this script with it.
  local i
  local -A hung=()
  for i in $(seq "$runs"); do
    for v in "${variants[@]}"; do
      if [ -n "${hung[$v]:-}" ]; then
        mkdir -p "$session/$v/$i"
        echo "skipped:gpu-hang" >"$session/$v/$i/status"
        continue
      fi
      sleep "$cool"
      one_run "$v" "$session/$v/$i"
      say "[$i/$runs] $v: $(cat "$session/$v/$i/status")"
      if [ -n "${game_stuck:-}" ]; then
        die "the game is stuck after a GPU hang and Steam will not launch it again; reboot"
      fi
      if [ "$(cat "$session/$v/$i/status")" = failed:gpu-hang ]; then
        hung[$v]=1
        say "$v hung the GPU; skipping its remaining runs"
      fi
    done
  done

  stop_load
  jq --arg end "$(date -Is)" '.end = $end' "$session/session.json" >"$session/session.json.new"
  mv "$session/session.json.new" "$session/session.json"
  "$GAME_BENCH_SUMMARY" summarise "$session"

  if grep -qv '^valid$' "$session"/*/*/status 2>/dev/null; then
    exit 1
  fi
}

cmd_build_time() {
  local runs=5 i start end times=()
  if [ "${1:-}" = -n ]; then runs=$2; fi
  [[ $runs =~ ^[1-9][0-9]*$ ]] || die "build-time: -n must be a positive number"
  for i in $(seq "$runs"); do
    start=$(date +%s.%N)
    nix build --rebuild --no-link --option cores 0 "$GAME_BENCH_LOAD_DRV^out" >/dev/null 2>&1 || true
    end=$(date +%s.%N)
    times+=("$(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.1f", e - s }')")
    say "[$i/$runs] ${times[-1]} s"
  done
  mkdir -p "$data"
  printf '%s\n' "${times[@]}" | sort -n | awk -v booted="$(readlink /run/booted-system)" \
    -v sched="$(read_or /sys/kernel/sched_ext/state unsupported)" -v date="$(date -Is)" '
    { t[NR] = $1 }
    END {
      med = (NR % 2) ? t[(NR + 1) / 2] : (t[NR / 2] + t[NR / 2 + 1]) / 2
      printf "median %.1f s, spread %.1f s (%d runs)\n", med, t[NR] - t[1], NR > "/dev/stderr"
      printf "%s\t%s\t%s\t%d\t%.1f\t%.1f\n", date, booted, sched, NR, med, t[NR] - t[1]
    }' >>"$data/build-time.tsv"
}

cmd_list() {
  echo "variants:"
  cfg '.variants | to_entries[] | "  \(.key)\t\(.value.description)\t[\(.value.workloads | join(","))]"'
  echo "workloads:"
  cfg '.workloads | to_entries[] | "  \(.key)\t\(.value.kind)\tapp \(.value.appid)"'
}

case "${1:-}" in
run)
  shift
  cmd_run "$@"
  ;;
compare)
  shift
  [ $# -ge 2 ] || die "compare needs at least two session directories"
  exec "$GAME_BENCH_SUMMARY" compare "$@"
  ;;
build-time)
  shift
  cmd_build_time "$@"
  ;;
restore)
  mkdir -p "$rt"
  session_live && die "a session is running; stop it first"
  replay_all
  rm -f "$runenv"
  ;;
list)
  cmd_list
  ;;
*)
  cat >&2 <<'EOF'
usage: game-bench run [-w WORKLOAD] [-v "V1 V2 ..."] [-n RUNS] [--load] [--cool SECS]
       game-bench compare SESSION_DIR SESSION_DIR [...]
       game-bench build-time [-n RUNS]
       game-bench restore
       game-bench list
EOF
  exit 2
  ;;
esac
