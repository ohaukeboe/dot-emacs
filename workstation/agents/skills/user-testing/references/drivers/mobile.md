# Driver: mobile-mcp (Android / iOS)

Tool names below are bare. The MCP prefix depends on how the server is
registered (`mcp__mobile-mcp__mobile_click_on_screen_at_coordinates`,
`mcp__plugin_hm_mobile-mcp__…`, …) — match on the suffix when probing.

Surface verified 2026-09-21. **Re-probe rather than trust this list**; it is
version-pinned and will drift.

## Verb mapping

| Verb | Tools |
| --- | --- |
| `observe` | `mobile_list_elements_on_screen`, `mobile_get_foreground_app`, `mobile_get_screen_size`, `mobile_get_orientation` |
| `act` | `mobile_click_on_screen_at_coordinates`, `mobile_double_tap_on_screen`, `mobile_long_press_on_screen_at_coordinates`, `mobile_swipe_on_screen`, `mobile_type_keys`, `mobile_press_button`, `mobile_open_url`, `mobile_launch_app`, `mobile_terminate_app` |
| `capture` | `mobile_take_screenshot`, `mobile_save_screenshot`, `mobile_start_screen_recording` / `mobile_stop_screen_recording` |
| `inspect` | `mobile_get_device_logs`, `mobile_list_crashes`, `mobile_get_crash` |
| *(setup)* | `mobile_list_available_devices`, `mobile_install_app`, `mobile_list_apps`, `mobile_set_location`, `mobile_set_orientation`, `mobile_clipboard`, `mobile_batch_commands` |

Start every session with `mobile_list_available_devices`. Record the device and
OS version in the session sheet header — a finding on one form factor is not a
finding on another.

## Leaks

### 1 · Element identity — coordinate-backed, and stale

`mobile_list_elements_on_screen` returns a `ref`, coordinates, and the display
text or accessibility label. Upstream is explicit: refs and coordinates **stay
valid only as long as the screen does not change**.

So:

- **Re-list after every navigation or layout change.** Not "usually" — always.
  A keyboard opening is a layout change. So is a toast, a banner, a spinner
  resolving.
- **Never cite coordinates in a finding.** They are not a durable identifier and
  they do not survive a different device, orientation or font scale.
- **Cite the element label plus a screenshot.** That pair is the repro. If the
  element has no label, that absence is itself an accessibility finding — record
  it as one and cite the element list output showing the gap.

There is no accessibility tree here in the web sense. An unlabelled control is
indistinguishable from a decorative one, so accessibility findings on this
driver are weaker than on web. Say so rather than overstating them.

### 2 · Log temporality — prospective only, and this one bites

`mobile_get_device_logs` captures **only logs emitted after the call starts**,
and stops after the entry limit or after 30 seconds of silence.

This inverts the web order. The `inspect` verb is therefore defined as:

```
arm     → start mobile_get_device_logs
act     → perform the action you want logs for
collect → read what the call returned
```

Reading logs *after* the interesting thing happened returns nothing. Nothing is
not evidence of a clean run — it is **missing evidence**, and treating it as a
clean run is exactly the false-negative this skill's evidence gate exists to
prevent.

Two consequences:

- Arm before triggering anything you might want to explain later, not after it
  surprises you.
- If you failed to arm in time, redo the step with the capture armed. If you
  cannot reproduce it, the finding goes in **Notes** with "logs not captured",
  never in **Bugs**.

Crashes are the exception: `mobile_list_crashes` / `mobile_get_crash` are
retrospective and will still have the report. Check them after any hard stop.

### 3 · Wait — absent

There is no `wait_for`. Poll instead:

```
re-observe → compare to previous element list → repeat until change or budget
```

Pick the budget before you start (e.g. 10 s) and **write it into any "no
response" finding**. Without a network inspector, this driver genuinely cannot
distinguish a slow backend from a dead control — so the honest finding is "no
observable change within Ns", plus what you checked (device logs armed, crash
list, foreground app unchanged). Do not upgrade that to "the button is broken".

## Mobile-only capabilities

Gate behind a probe, use as optional charters:

- `mobile_press_button` — hardware back, home, volume. The **back button is the
  highest-yield mobile charter there is**: back out of every screen in a flow
  and see what survives. It has no web equivalent.
- `mobile_set_orientation` — rotate mid-flow; watch for lost input state.
- `mobile_set_location` — location-gated features, and wrong-region behaviour.
- `mobile_install_app` / `mobile_launch_app` / `mobile_terminate_app` — true
  first-run state (fresh install), and kill-and-relaunch to test state
  restoration.
- `mobile_list_crashes` / `mobile_get_crash` — always check after an app
  disappears. A crash report is the strongest evidence this driver produces.
- `mobile_start_screen_recording` — for gesture or animation findings a still
  frame cannot show.
- `mobile_clipboard` — paste-into-field flows, and verifying "copied" actions.
- `mobile_batch_commands` — replaying a known repro quickly. Do not use it
  during exploration; you lose the per-step observe that the trajectory needs.

## Capture conventions

- `mobile_take_screenshot` before and after any action producing a finding.
- `mobile_save_screenshot` to write evidence to a stable path the session sheet
  can cite; the validator checks that path exists.
- Prefer a screen recording over a screenshot for anything involving a gesture,
  a transition, or a disappearing element.
