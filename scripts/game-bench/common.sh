# Shared by game-bench and game-bench-priv: modules/gaming/bench/packages.nix
# prepends this file to both scripts, so both find the same card.

# The amdgpu hwmon directory with a power limit; fails without one.
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

# Running a non-Zen kernel? Either the default (stock since
# docs/gaming-benchmarks.md) or the comparison entry tagged "stock".
booted_stock() {
  case "$(uname -r)" in
  *zen*) return 1 ;;
  esac
  return 0
}
