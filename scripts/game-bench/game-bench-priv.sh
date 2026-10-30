# game-bench-priv: the root half of game-bench, run as
# `sudo -n game-bench-priv <subcommand> [arg]` through one NOPASSWD rule
# (modules/gaming/bench/default.nix, docs/adr/0009-game-benchmark-harness.md).
#
# Contract: specs/008-game-performance-tuning/contracts/game-bench-priv.md.
# Every write target is a fixed path in this file; arguments are validated
# against fixed sets or digit patterns and never used as paths. An invalid
# argument exits 2 and changes nothing.
#
# GAME_BENCH_SCX (runtimeEnv) is the scx package's bin directory.

state_dir=/run/game-bench-priv
debug_sched=/sys/kernel/debug/sched

die() {
  echo "game-bench-priv: $*" >&2
  exit 2
}

amdgpu_hwmon() {
  local h
  for h in /sys/class/hwmon/hwmon*; do
    if [ "$(cat "$h/name" 2>/dev/null)" = amdgpu ] && [ -e "$h/power1_cap" ]; then
      echo "$h"
      return 0
    fi
  done
  echo "game-bench-priv: no amdgpu hwmon with power1_cap" >&2
  exit 1
}

# Running a non-Zen kernel? Either the default (stock since
# docs/gaming-benchmarks.md) or the comparison entry tagged "stock".
booted_stock() {
  case "$(uname -r)" in
  *zen*) return 1 ;;
  esac
  return 0
}

# The selected entry of a sysfs list such as "none [kyber] bfq" or
# "none voluntary (full) lazy".
selected() {
  sed -n 's/.*[[(]\([^])]*\)[])].*/\1/p' "$1"
}

scx_state() {
  cat /sys/kernel/sched_ext/state 2>/dev/null || echo unsupported
}

cmd=${1:-}
arg=${2:-}

case "$cmd" in
check)
  exit 0
  ;;

scx-start)
  case "$arg" in
  scx_bpfland | scx_lavd) ;;
  *) die "scx-start: expected scx_bpfland or scx_lavd, got '$arg'" ;;
  esac
  systemctl stop game-bench-scx.service 2>/dev/null || true
  systemd-run --unit=game-bench-scx --collect --quiet "$GAME_BENCH_SCX/$arg"
  for _ in $(seq 50); do
    if [ "$(scx_state)" = enabled ]; then exit 0; fi
    sleep 0.1
  done
  systemctl stop game-bench-scx.service 2>/dev/null || true
  echo "game-bench-priv: $arg did not reach sched_ext state 'enabled' within 5 s" >&2
  exit 1
  ;;

scx-stop)
  systemctl stop game-bench-scx.service 2>/dev/null || true
  ;;

s76-stop)
  systemctl stop system76-scheduler.service
  ;;

s76-start)
  systemctl start system76-scheduler.service
  ;;

zen-knobs)
  case "$arg" in
  on)
    booted_stock || die "zen-knobs: the running kernel is Zen, which already has these values"
    mkdir -p "$state_dir"
    if [ ! -e "$state_dir/zen-knobs" ]; then
      {
        echo "preempt=$(selected "$debug_sched/preempt")"
        echo "base_slice_ns=$(cat "$debug_sched/base_slice_ns")"
        echo "migration_cost_ns=$(cat "$debug_sched/migration_cost_ns")"
        echo "nr_migrate=$(cat "$debug_sched/nr_migrate")"
        for q in /sys/block/nvme*/queue/scheduler; do
          if [ -e "$q" ]; then echo "iosched:$q=$(selected "$q")"; fi
        done
      } >"$state_dir/zen-knobs"
    fi
    # Zen's ZEN_INTERACTIVE values (zen-kernel commit 28014767dba9).
    echo full >"$debug_sched/preempt"
    echo 400000 >"$debug_sched/base_slice_ns"
    echo 300000 >"$debug_sched/migration_cost_ns"
    echo 8 >"$debug_sched/nr_migrate"
    for q in /sys/block/nvme*/queue/scheduler; do
      if [ -e "$q" ]; then echo kyber >"$q"; fi
    done
    ;;
  off)
    [ -e "$state_dir/zen-knobs" ] || exit 0
    while IFS='=' read -r key value; do
      case "$key" in
      preempt | base_slice_ns | migration_cost_ns | nr_migrate)
        if [[ $value =~ ^[a-z0-9]+$ ]]; then echo "$value" >"$debug_sched/$key"; fi
        ;;
      iosched:/sys/block/nvme*/queue/scheduler)
        q=${key#iosched:}
        if [[ $value =~ ^[a-z-]+$ ]] && [ -e "$q" ]; then echo "$value" >"$q"; fi
        ;;
      esac
    done <"$state_dir/zen-knobs"
    rm -f "$state_dir/zen-knobs"
    ;;
  status)
    echo "preempt=$(selected "$debug_sched/preempt")"
    echo "base_slice_ns=$(cat "$debug_sched/base_slice_ns")"
    ;;
  *) die "zen-knobs: expected on, off or status, got '$arg'" ;;
  esac
  ;;

gpu-profile)
  dev=$(readlink -f "$(amdgpu_hwmon)/device")
  case "$arg" in
  3d-full-screen)
    index=$(sed -n 's/^ *\([0-9]\+\) *3D_FULL_SCREEN.*/\1/p' "$dev/pp_power_profile_mode" | head -n1)
    [ -n "$index" ] || {
      echo "game-bench-priv: no 3D_FULL_SCREEN profile on this GPU" >&2
      exit 1
    }
    echo manual >"$dev/power_dpm_force_performance_level"
    echo "$index" >"$dev/pp_power_profile_mode"
    ;;
  default)
    echo manual >"$dev/power_dpm_force_performance_level"
    echo 0 >"$dev/pp_power_profile_mode"
    echo auto >"$dev/power_dpm_force_performance_level"
    ;;
  *) die "gpu-profile: expected 3d-full-screen or default, got '$arg'" ;;
  esac
  ;;

gpu-cap)
  h=$(amdgpu_hwmon)
  case "$arg" in
  default)
    cat "$h/power1_cap_default" >"$h/power1_cap"
    ;;
  *)
    [[ $arg =~ ^[0-9]{1,4}$ ]] || die "gpu-cap: expected whole watts or 'default', got '$arg'"
    min=$(($(cat "$h/power1_cap_min") / 1000000))
    max=$(($(cat "$h/power1_cap_max") / 1000000))
    if ((arg < min || arg > max)); then
      die "gpu-cap: $arg W is outside this card's range $min-$max W; nothing changed"
    fi
    echo $((arg * 1000000)) >"$h/power1_cap"
    ;;
  esac
  ;;

gpu-undervolt)
  # Overdrive's one voltage offset for the whole V/F curve (SMU 13,
  # docs.kernel.org/gpu/amdgpu/thermal.html): `vo -<mV>` then commit `c`.
  # 0 removes the offset. A driver reset also clears it.
  if ! [[ $arg =~ ^(0|[1-9][0-9]{0,2})$ ]] || ((arg > 200)); then
    die "gpu-undervolt: expected 0-200 (mV below stock), got '$arg'"
  fi
  od="$(readlink -f "$(amdgpu_hwmon)/device")/pp_od_clk_voltage"
  [ -e "$od" ] || {
    echo "game-bench-priv: amdgpu overdrive is off (no pp_od_clk_voltage); set modules.gaming.gpu.overdrive.enable" >&2
    exit 1
  }
  if ((arg == 0)); then echo "vo 0" >"$od"; else echo "vo -$arg" >"$od"; fi
  echo c >"$od"
  ;;

gpu-cap-range)
  h=$(amdgpu_hwmon)
  echo "$(($(cat "$h/power1_cap_min") / 1000000)) $(($(cat "$h/power1_cap_default") / 1000000)) $(($(cat "$h/power1_cap_max") / 1000000))"
  ;;

*)
  die "unknown subcommand '$cmd'; see contracts/game-bench-priv.md"
  ;;
esac
