"""game-bench-summary: summarise and compare game-bench sessions.

  game-bench-summary summarise SESSION_DIR
  game-bench-summary compare SESSION_DIR SESSION_DIR [...]

Metric definitions are in
specs/008-game-performance-tuning/data-model.md ("Metrics").
Proton runs are the game's own per-frame log (game-frames.csv), else a
MangoHud CSV (frames.csv), with GPU power, clock and junction temperature
from game-bench's gpu.csv (power.csv in sessions before it).
Native runs are Factorio's --benchmark-verbose output (factorio.out).
"""

import csv
import json
import math
import statistics
import sys
from pathlib import Path

MIN_SAMPLES = 100
# SC-003: a baseline noisier than this cannot decide anything.
NOISE_P1 = 0.05
NOISE_AVG = 0.03
# Columns in versions that differ between kernels on purpose.
KERNEL_FIELDS = {"kernel", "bootedSystem"}


def percentile(values, pct):
    """Nearest-rank percentile of an already sorted list."""
    rank = math.ceil(pct / 100 * len(values))
    return values[max(rank, 1) - 1]


def read_mangohud(path):
    """Frame times (ms) and GPU power (W) from a MangoHud CSV."""
    lines = path.read_text().splitlines()
    start = next(
        (i for i, line in enumerate(lines) if line.startswith("fps,")),
        None,
    )
    if start is None:
        return [], []
    frames, power = [], []
    for row in csv.DictReader(lines[start:]):
        try:
            frames.append(float(row["frametime"]))
        except (KeyError, TypeError, ValueError):
            continue
        try:
            power.append(float(row["gpu_power"]))
        except (KeyError, TypeError, ValueError):
            pass
    return frames, power


def read_game_frames(path):
    """Frame times (ms) from Cyberpunk's benchmarkResults frames.csv."""
    frames = []
    with path.open(newline="") as f:
        for row in csv.reader(f):
            try:
                frames.append(float(row[1]))
            except (IndexError, ValueError):
                continue
    return frames


def benchmark_window(run_dir):
    """(start, end) epoch seconds of the game's benchmark pass, or None.

    The pass ends when the game writes frames.csv (copied with its mtime)
    and lasts game.json's Data.time seconds.
    """
    frames, summary = run_dir / "game-frames.csv", run_dir / "game.json"
    if not (frames.exists() and summary.exists()):
        return None
    try:
        data = json.loads(summary.read_text(encoding="utf-8-sig"))
        seconds = float(data["Data"]["time"])
    except (KeyError, TypeError, ValueError):
        return None
    end = frames.stat().st_mtime
    return end - seconds, end


def read_power(path, window):
    """GPU power (W) from power.csv (`epoch,microwatts`) inside window."""
    power = []
    for line in path.read_text().splitlines():
        try:
            when, microwatts = (float(x) for x in line.split(","))
        except ValueError:
            continue
        if window is None or window[0] <= when <= window[1]:
            power.append(microwatts / 1e6)
    return power


def read_gpu(path, window):
    """Power (W), GFX clock (MHz), junction temperature (°C) from gpu.csv.

    Only samples inside window count; a missing cell skips that value.
    """
    power, sclk, junction = [], [], []
    columns = (
        (power, "power_uw", 1e6),
        (sclk, "sclk_hz", 1e6),
        (junction, "junction_mc", 1e3),
    )
    with path.open(newline="") as f:
        for row in csv.DictReader(f):
            try:
                when = float(row["epoch"])
            except (KeyError, TypeError, ValueError):
                continue
            if window is not None and not window[0] <= when <= window[1]:
                continue
            for out, key, scale in columns:
                try:
                    out.append(float(row[key]) / scale)
                except (KeyError, TypeError, ValueError):
                    pass
    return power, sclk, junction


def read_factorio(path):
    """Tick times (ms) from Factorio's --benchmark-verbose output.

    The header is the first comma-separated line starting with "tick";
    the tick time is the wholeUpdate column (ns), or else the column
    after the tick number.
    """
    lines = path.read_text().splitlines()
    start = next(
        (
            i
            for i, line in enumerate(lines)
            if line.lower().startswith("tick") and "," in line
        ),
        None,
    )
    if start is None:
        return []
    header = [h.strip() for h in lines[start].split(",")]
    col = header.index("wholeUpdate") if "wholeUpdate" in header else 1
    ticks = []
    for line in lines[start + 1:]:
        cells = line.split(",")
        if len(cells) <= col:
            continue
        try:
            ticks.append(float(cells[col]) / 1e6)
        except ValueError:
            continue
    return ticks


def run_metrics(run_dir, kind):
    """(metrics, reason): metrics is None when the run does not count."""
    status_file = run_dir / "status"
    status = status_file.read_text().strip() if status_file.exists() else ""
    if status != "valid":
        return None, status or "missing status"
    if kind == "native":
        samples = read_factorio(run_dir / "factorio.out") if (
            run_dir / "factorio.out"
        ).exists() else []
        power, sclk, junction = [], [], []
    else:
        game_frames = run_dir / "game-frames.csv"
        mangohud = run_dir / "frames.csv"
        samples, power, sclk, junction = [], [], [], []
        if game_frames.exists():
            samples = read_game_frames(game_frames)
        elif mangohud.exists():
            samples, power = read_mangohud(mangohud)
        gpu_csv, power_csv = run_dir / "gpu.csv", run_dir / "power.csv"
        if gpu_csv.exists():
            power, sclk, junction = read_gpu(
                gpu_csv, benchmark_window(run_dir)
            )
        elif power_csv.exists():
            power = read_power(power_csv, benchmark_window(run_dir))
    if len(samples) < MIN_SAMPLES:
        return None, "excluded:short"
    ordered = sorted(samples)
    if kind == "native":
        metrics = {
            "avg": statistics.fmean(samples),
            "p1": percentile(ordered, 99),
            "p01": percentile(ordered, 99.9),
        }
    else:
        metrics = {
            "avg": 1000 * len(samples) / sum(samples),
            "p1": 1000 / percentile(ordered, 99),
            "p01": 1000 / percentile(ordered, 99.9),
        }
    metrics["power"] = statistics.median(power) if power else None
    metrics["sclk"] = statistics.median(sclk) if sclk else None
    metrics["tj_max"] = max(junction) if junction else None
    return metrics, "valid"


def spread(values):
    return max(values) - min(values) if values else 0.0


def summarise(session_dir):
    session = json.loads((session_dir / "session.json").read_text())
    kind = session.get("kind", "proton")
    unit = "ms" if kind == "native" else "fps"
    rows = []
    for variant in session["variants"]:
        vdir = session_dir / variant
        runs = sorted(
            (p for p in vdir.iterdir() if p.is_dir()),
            key=lambda p: int(p.name) if p.name.isdigit() else 0,
        ) if vdir.is_dir() else []
        good, excluded = [], 0
        for run in runs:
            metrics, _ = run_metrics(run, kind)
            if metrics is None:
                excluded += 1
            else:
                good.append(metrics)
        row = {"variant": variant, "runs": len(good), "excluded": excluded}
        for key in ("avg", "p1", "p01"):
            values = [m[key] for m in good]
            row[key] = statistics.median(values) if values else None
            row[key + "_spread"] = spread(values)
        power = [m["power"] for m in good if m["power"] is not None]
        row["power"] = statistics.median(power) if power else None
        sclk = [m["sclk"] for m in good if m["sclk"] is not None]
        row["sclk"] = round(statistics.median(sclk)) if sclk else None
        tj = [m["tj_max"] for m in good if m["tj_max"] is not None]
        row["tj_max"] = round(max(tj)) if tj else None
        rows.append(row)

    columns = [
        "variant", "runs", "excluded", "avg", "avg_spread", "p1",
        "p1_spread", "p01", "p01_spread", "power", "sclk", "tj_max",
    ]
    with open(session_dir / "summary.tsv", "w") as out:
        out.write("\t".join(columns) + "\tunit\n")
        for row in rows:
            out.write("\t".join(fmt(row[c]) for c in columns))
            out.write("\t" + unit + "\n")

    text = render(rows, unit, session)
    (session_dir / "summary.txt").write_text(text)
    sys.stdout.write(text)


def fmt(value):
    if value is None:
        return "-"
    if isinstance(value, float):
        return f"{value:.2f}"
    return str(value)


def noisy(rows):
    base = next((r for r in rows if r["variant"] == "baseline"), None)
    if not base or not base["runs"]:
        return False
    return (
        base["p1_spread"] > NOISE_P1 * base["p1"]
        or base["avg_spread"] > NOISE_AVG * base["avg"]
    )


def render(rows, unit, session):
    better = "lower" if unit == "ms" else "higher"
    head = [
        "variant", "runs", "excl", "p1", "±", "p0.1", "±", "avg", "±",
        "power W", "GPU MHz", "Tj max C",
    ]
    table = [head]
    for r in rows:
        table.append([
            r["variant"], str(r["runs"]), str(r["excluded"]),
            fmt(r["p1"]), fmt(r["p1_spread"]),
            fmt(r["p01"]), fmt(r["p01_spread"]),
            fmt(r["avg"]), fmt(r["avg_spread"]),
            fmt(r["power"]), fmt(r["sclk"]), fmt(r["tj_max"]),
        ])
    widths = [max(len(row[i]) for row in table) for i in range(len(head))]
    lines = [
        f"workload {session.get('workload')} ({unit}, {better} is better), "
        f"load {'on' if session.get('load') else 'off'}"
    ]
    for row in table:
        lines.append("  ".join(c.ljust(w) for c, w in zip(row, widths)))
    if session.get("na"):
        lines.append("n/a for this workload: " + " ".join(session["na"]))
    if noisy(rows):
        lines.append(
            "NOISY: baseline spread exceeds 5% (1% low) or 3% (avg); "
            "do not decide on this session"
        )
    return "\n".join(lines) + "\n"


def label(session):
    kernel = session.get("versions", {}).get("kernel", "")
    tag = "zen" if "zen" in kernel else "stock"
    return f"{tag}/{'load' if session.get('load') else 'idle'}"


def compare(dirs):
    sessions = []
    for d in dirs:
        session = json.loads((d / "session.json").read_text())
        with open(d / "summary.tsv") as f:
            rows = list(csv.DictReader(f, delimiter="\t"))
        sessions.append((d, session, rows))

    by_workload = {}
    for entry in sessions:
        by_workload.setdefault(entry[1].get("workload"), []).append(entry)

    for workload, entries in by_workload.items():
        print(f"== {workload}")
        table = [["session", "variant", "runs", "p1", "±", "p0.1", "±",
                  "avg", "±", "unit"]]
        for d, session, rows in entries:
            for r in rows:
                table.append([
                    label(session), r["variant"], r["runs"], r["p1"],
                    r["p1_spread"], r["p01"], r["p01_spread"], r["avg"],
                    r["avg_spread"], r["unit"],
                ])
        widths = [max(len(row[i]) for row in table)
                  for i in range(len(table[0]))]
        for row in table:
            print("  ".join(c.ljust(w) for c, w in zip(row, widths)))

        keys = set()
        for _, session, _ in entries:
            keys |= set(session.get("versions", {}))
        differ = sorted(
            k for k in keys - KERNEL_FIELDS
            if len({s.get("versions", {}).get(k) for _, s, _ in entries}) > 1
        )
        if differ:
            print("WARNING: versions differ: " + " ".join(differ))


def main(argv):
    if len(argv) >= 3 and argv[1] == "summarise":
        summarise(Path(argv[2]))
    elif len(argv) >= 4 and argv[1] == "compare":
        compare([Path(a) for a in argv[2:]])
    else:
        sys.stderr.write(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
