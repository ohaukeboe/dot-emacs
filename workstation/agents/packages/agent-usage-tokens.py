"""Claude Code token use and plan limits for the Mango rail's usage popup.

Reads the session transcripts under the Claude directory and writes
tokens.json, and asks Anthropic's OAuth usage endpoint for the plan limits
and writes limits.json, as specified in
specs/013-mango-islands-shell/contracts/usage-record.md.
"""

import json
import os
import sys
import tempfile
import time
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path

# Overridable so the fixture test can serve a file:// response.
USAGE_URL = os.environ.get("AGENT_USAGE_URL", "https://api.anthropic.com/api/oauth/usage")
DAYS = 7
# Transcripts not touched for this long cannot hold a message from the window.
MAX_AGE_SECONDS = (DAYS + 1) * 86400


def state_dir():
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    return Path(base) / "agent-usage"


def claude_dir():
    return Path(os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude"))


def message_tokens(usage):
    keys = (
        "input_tokens",
        "output_tokens",
        "cache_creation_input_tokens",
        "cache_read_input_tokens",
    )
    return sum(usage.get(k) or 0 for k in keys)


def collect(projects, today, now):
    first = today - timedelta(days=DAYS - 1)
    per_day = {first + timedelta(days=i): 0 for i in range(DAYS)}
    per_model = {}
    seen = set()
    for path in projects.rglob("*.jsonl"):
        try:
            if now - path.stat().st_mtime > MAX_AGE_SECONDS:
                continue
            lines = path.open(encoding="utf-8", errors="replace")
        except OSError:
            continue
        with lines:
            for line in lines:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(entry, dict) or entry.get("type") != "assistant":
                    continue
                message = entry.get("message")
                if not isinstance(message, dict):
                    continue
                usage = message.get("usage")
                if not isinstance(usage, dict):
                    continue
                # A streamed message is written once per content block.
                key = (message.get("id"), entry.get("requestId"))
                if key in seen:
                    continue
                seen.add(key)
                try:
                    stamp = entry["timestamp"].replace("Z", "+00:00")
                    day = datetime.fromisoformat(stamp).astimezone().date()
                except (KeyError, AttributeError, ValueError):
                    continue
                if day not in per_day:
                    continue
                tokens = message_tokens(usage)
                per_day[day] += tokens
                model = message.get("model") or "unknown"
                per_model[model] = per_model.get(model, 0) + tokens
    return per_day, per_model


def write_atomic(target, record):
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=f".{target.stem}.")
    try:
        with os.fdopen(fd, "w") as out:
            json.dump(record, out)
            out.write("\n")
        os.replace(tmp, target)
    except BaseException:
        os.unlink(tmp)
        raise


def limits_record(usage, now):
    """Map the endpoint's windows (utilization 0-100, ISO resets_at) to the contract."""

    def window(w):
        if not isinstance(w, dict) or w.get("utilization") is None:
            return None
        resets = w.get("resets_at")
        return {
            "used_percentage": round(w["utilization"]),
            "resets_at": int(datetime.fromisoformat(resets).timestamp()) if resets else None,
        }

    session, weekly = window(usage.get("five_hour")), window(usage.get("seven_day"))
    if session is None and weekly is None:
        return None
    return {"updated_at": int(now), "session": session, "weekly": weekly}


def fetch_limits(now):
    """Plan limits from the token Claude Code keeps; None when there is none.

    Never refreshes the token: that would rotate the refresh token Claude
    Code holds. An expired token waits until Claude Code next refreshes it.
    """
    try:
        creds = json.loads((claude_dir() / ".credentials.json").read_text())
    except (OSError, ValueError):
        return None
    oauth = creds.get("claudeAiOauth") or {}
    token = oauth.get("accessToken")
    if not token or (oauth.get("expiresAt") or 0) / 1000 < now:
        return None
    request = urllib.request.Request(
        USAGE_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": "agent-usage",
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return limits_record(json.load(response), now)


def main():
    now = time.time()
    try:
        limits = fetch_limits(now)
        if limits:
            write_atomic(state_dir() / "limits.json", limits)
    except Exception as err:  # limits.json keeps its last record; readers mark it stale
        print(f"agent-usage: limits: {type(err).__name__}: {err}", file=sys.stderr)
    target = state_dir() / "tokens.json"
    today = date.fromtimestamp(now)
    try:
        per_day, per_model = collect(claude_dir() / "projects", today, now)
    except Exception as err:  # keep the last good record, mark it
        try:
            record = json.loads(target.read_text())
        except (OSError, ValueError):
            record = {}
        record["updated_at"] = int(now)
        record["error"] = f"{type(err).__name__}: {err}".splitlines()[0]
        write_atomic(target, record)
        print(f"agent-usage: {record['error']}", file=sys.stderr)
        return 1
    days = [{"date": d.isoformat(), "tokens": n} for d, n in sorted(per_day.items())]
    models = [
        {"model": m, "tokens": n}
        for m, n in sorted(per_model.items(), key=lambda kv: kv[1], reverse=True)
        if n > 0
    ]
    record = {
        "updated_at": int(now),
        "days": days,
        "models": models,
        "week_tokens": sum(d["tokens"] for d in days),
    }
    write_atomic(target, record)
    print(f"agent-usage: {record['week_tokens']} tokens over {DAYS} days")
    return 0


if __name__ == "__main__":
    sys.exit(main())
