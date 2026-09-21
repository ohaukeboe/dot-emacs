# Driver: chrome-devtools-mcp (web)

Tool names below are bare. The MCP prefix depends on how the server is
registered (`mcp__chrome-devtools__click`,
`mcp__plugin_hm_chrome-devtools__click`, …) — match on the suffix when probing.

Surface verified 2026-09-21. **Re-probe rather than trust this list**; it is
version-pinned and will drift.

## Verb mapping

| Verb | Tools |
| --- | --- |
| `observe` | `take_snapshot` (a11y-tree text snapshot with per-element `uid`), `list_pages`, `select_page` |
| `act` | `click`, `fill`, `fill_form`, `hover`, `drag`, `type_text`, `press_key`, `select_page`, `navigate_page`, `new_page`, `close_page`, `handle_dialog`, `upload_file` |
| `capture` | `take_screenshot` |
| `inspect` | `list_console_messages`, `get_console_message`, `list_network_requests`, `get_network_request`, `evaluate_script`, `lighthouse_audit`, `performance_start_trace` / `performance_stop_trace` / `performance_analyze_insight`, `take_heapsnapshot` |
| *(other)* | `wait_for`, `emulate`, `resize_page` |

Prefer `take_snapshot` over `take_screenshot` for deciding what to act on. Take
the screenshot as **evidence**, not as input to a decision — the snapshot is
what carries element identity.

## Leaks

### 1 · Element identity — the good case

`take_snapshot` returns semantic `uid`s over the accessibility tree. A `uid` is
**snapshot-scoped**: re-snapshot after anything that changes the page, and use
the new `uid`s.

Cite a web element in a finding as **`uid` + role + accessible name**. The name
and role survive a re-render; the `uid` does not, and is only there to make the
repro replayable inside one snapshot.

Because this driver exposes the a11y tree directly, accessibility findings here
are unusually cheap and unusually strong: a control with no accessible name, a
wrong role, or an unreachable element shows up in the snapshot itself.

### 2 · Log temporality — retrospective

`list_console_messages` returns messages **since the last navigation**. So the
natural order works: act, then read.

The skill's `inspect` verb is defined as **arm → act → collect** so mobile can
work at all. On this driver, **the arming step is a no-op** — skip it and read
after acting. Do not invent a "start capturing" call; there isn't one.

Navigation clears the buffer. Collect console output *before* navigating away,
or the evidence for the screen you just left is gone.

### 3 · Wait — available

`wait_for` exists. Use it instead of polling.

Combined with `list_network_requests`, this driver can usually tell *slow* from
*broken*: a pending or failed request is evidence, a quiet network with no
DOM change is a different finding. Record which one you saw. This is strictly
more evidence than the mobile driver can produce for the same symptom — do not
write cross-driver findings as if they were equally grounded.

## Web-only capabilities

Gate these behind a probe and use them as **optional charters**, never as part
of the core loop:

- `emulate` — device, network throttling, CPU throttling. This is how you run a
  "slow 3G" or "low-end device" persona for real instead of imagining it.
- `resize_page` — viewport widths; the honest way to test responsive layout.
- `lighthouse_audit` — accessibility/performance/SEO audit as corroborating
  evidence. Its findings are machine-produced and citable, but they are its
  findings, not yours: attribute them.
- `performance_start_trace` / `performance_analyze_insight` — only when the
  charter is about perceived slowness.
- `evaluate_script` — read state the UI does not show. Keep it to reading. A
  script that mutates app state invalidates the rest of the session as a user
  test.
- `handle_dialog` — native `alert` / `confirm` / `prompt` block everything else
  until handled.
- `upload_file` — file-picker flows.

## Capture conventions

- `take_screenshot` immediately before and immediately after any action that
  produces a finding.
- Save the `take_snapshot` text alongside the screenshot for any accessibility
  or "element not reachable" finding — the snapshot *is* the evidence there.
- For a failed request, cite `get_network_request` output, not a summary of it.
