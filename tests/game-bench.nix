# game-bench's pure parts against generated fixtures.
#
#   nix build .#checks.x86_64-linux.game-bench -L
#
# specs/008-game-performance-tuning. The harness itself drives Steam, the
# GPU and sudo, which a build sandbox cannot; quickstart.md covers those.
# This checks what decides results and what protects normal play:
#   - summary: medians, a short run excluded, the noise flag, the game's own
#     frame log with windowed power, Factorio ticks.
#   - compare: warns when Mesa differs, not when only the kernel does.
#   - game-bench-wrap: passes through with no lock, a dead lock, or no
#     run.env, and applies run.env only for a live session.
{
  runCommand,
  callPackage,
  python3,
  coreutils,
}:

let
  bench = callPackage ../modules/gaming/bench/packages.nix {
    benchConfig = import ../modules/gaming/bench/variants.nix;
  };
in
runCommand "game-bench"
  {
    nativeBuildInputs = [
      bench.game-bench-summary
      bench.game-bench-wrap
      python3
      coreutils
    ];
  }
  ''
    fail() { echo "tests/game-bench.nix: $*"; exit 1; }

    # A MangoHud CSV: system-info lines, then per-frame rows. $1 = frames,
    # $2 = frametime in ms (constant, plus one slow frame per 100).
    mangohud() {
      echo "os,cpu,gpu,ram,kernel,driver,cpuscheduler"
      echo "NixOS,9950X,7900XT,64,7.2,mesa,eevdf"
      echo "fps,frametime,cpu_load,gpu_power,elapsed"
      awk -v n="$1" -v ft="$2" 'BEGIN {
        for (i = 1; i <= n; i++) {
          t = (i % 100 == 0) ? ft * 3 : ft
          printf "%.1f,%.3f,50,250,%d\n", 1000 / t, t, i
        }
      }'
    }

    run() { # session variant n frames frametime
      mkdir -p "$1/$2/$3"
      mangohud "$4" "$5" > "$1/$2/$3/frames.csv"
      echo valid > "$1/$2/$3/status"
    }

    session_json() { # dir workload kind variants mesa booted
      mkdir -p "$1"
      cat > "$1/session.json" <<EOF
    {"workload":"$2","kind":"$3","variants":$4,"na":[],"runs":3,"load":false,
     "versions":{"mesa":"$5","kernel":"7.2.11","bootedSystem":"$6"}}
    EOF
    }

    # --- summary, proton ------------------------------------------------
    s=proton
    session_json $s cyberpunk proton '["baseline","gamemode"]' 26.2.5 nixos-system-desktop-26.11
    for i in 1 2 3; do run $s baseline $i 1000 10; done
    run $s gamemode 1 1000 8
    run $s gamemode 2 1000 8
    run $s gamemode 3 50 8 # too short: excluded
    game-bench-summary summarise $s > out.txt

    awk -F'\t' '$1 == "gamemode" { exit !($2 == 2 && $3 == 1) }' $s/summary.tsv \
      || fail "gamemode should have 2 valid runs and 1 excluded: $(cat $s/summary.tsv)"
    awk -F'\t' '$1 == "baseline" { exit !($4 > 98 && $4 < 100) }' $s/summary.tsv \
      || fail "baseline avg fps should be about 98: $(cat $s/summary.tsv)"
    grep -q NOISY out.txt && fail "steady baseline flagged as noisy"

    # A noisy baseline is flagged (SC-003).
    n=noisy
    session_json $n cyberpunk proton '["baseline"]' 26.2.5 nixos-system-desktop-26.11
    run $n baseline 1 1000 10
    run $n baseline 2 1000 12
    game-bench-summary summarise $n | grep -q NOISY || fail "noisy baseline not flagged"

    # The game's own frame log wins over MangoHud's, and power counts only
    # samples inside the pass: game.json's time, ending at the log's mtime.
    g=gamelog
    session_json $g cyberpunk proton '["baseline"]' 26.2.5 nixos-system-desktop-26.11
    run $g baseline 1 1000 10
    {
      echo "Frame index, Frame time (ms), DLSS Frame Generation (ms)"
      awk 'BEGIN { for (i = 0; i < 500; i++) printf "%d, 20.00, 20.00\n", i }'
    } > $g/baseline/1/game-frames.csv
    touch -d @2000 $g/baseline/1/game-frames.csv
    echo '{"Data":{"time":100.0}}' > $g/baseline/1/game.json
    printf '1850.5,50000000\n1950.5,200000000\n1990.5,200000000\n2050.5,50000000\n' \
      > $g/baseline/1/power.csv
    game-bench-summary summarise $g > /dev/null
    awk -F'\t' '$1 == "baseline" { exit !($4 > 49.9 && $4 < 50.1 && $10 > 199 && $10 < 201) }' \
      $g/summary.tsv || fail "game log and windowed power not used: $(cat $g/summary.tsv)"

    # --- summary, native (Factorio) ------------------------------------
    f=native
    session_json $f factorio native '["baseline"]' 26.2.5 nixos-system-desktop-26.11
    mkdir -p $f/baseline/1
    {
      echo "Loading map benchmark.zip"
      echo "tick,timestamp,wholeUpdate"
      awk 'BEGIN { for (i = 0; i < 500; i++) printf "%d,%d,%d\n", i, i * 1000, 2000000 }'
      echo "Performed 500 updates in 1000.000 ms"
    } > $f/baseline/1/factorio.out
    echo valid > $f/baseline/1/status
    game-bench-summary summarise $f > /dev/null
    awk -F'\t' '$1 == "baseline" { exit !($4 == "2.00" && $NF == "ms") }' $f/summary.tsv \
      || fail "factorio mean tick should be 2.00 ms: $(cat $f/summary.tsv)"

    # --- compare ---------------------------------------------------------
    k=stock
    session_json $k cyberpunk proton '["baseline","gamemode"]' 26.2.5 nixos-system-desktop-stock-26.11
    cp -r $s/baseline $s/gamemode $k/
    game-bench-summary summarise $k > /dev/null
    game-bench-summary compare $s $k > cmp.txt
    grep -q "versions differ" cmp.txt && fail "kernel-only difference must not warn: $(cat cmp.txt)"
    grep -q "stock/idle" cmp.txt || fail "stock session not labelled: $(cat cmp.txt)"

    m=mesa
    session_json $m cyberpunk proton '["baseline","gamemode"]' 26.3.0 nixos-system-desktop-26.11
    cp -r $s/baseline $s/gamemode $m/
    game-bench-summary summarise $m > /dev/null
    game-bench-summary compare $s $m | grep -q "versions differ: mesa" \
      || fail "differing Mesa not warned"

    # --- game-bench-wrap -------------------------------------------------
    export XDG_RUNTIME_DIR="$PWD/rt"
    mkdir -p rt/game-bench
    printf 'GB_ENV=RADV_PERFTEST=nggc\nGB_MANGOHUD=no_display\nGB_ENV=bad-name=x\n' > rt/game-bench/run.env

    unset MANGOHUD RADV_PERFTEST
    game-bench-wrap env > env.txt
    grep -q '^MANGOHUD=' env.txt && fail "wrap applied run.env without a lock"

    sleep 60 & dead=$!; kill $dead; wait $dead 2>/dev/null || true
    echo $dead > rt/game-bench/lock
    game-bench-wrap env > env.txt
    grep -q '^MANGOHUD=' env.txt && fail "wrap applied run.env for a dead session"

    echo $$ > rt/game-bench/lock
    game-bench-wrap env > env.txt
    grep -q '^MANGOHUD=1$' env.txt || fail "wrap ignored run.env in a live session"
    grep -q '^RADV_PERFTEST=nggc$' env.txt || fail "wrap did not export GB_ENV"
    grep -q '^bad-name' env.txt && fail "wrap exported an invalid name"

    rm rt/game-bench/run.env
    game-bench-wrap env > env.txt
    grep -q '^MANGOHUD=' env.txt && fail "wrap applied settings with no run.env"

    touch "$out"
  ''
