---
name: verify-quickshell
description: See a Mango Quickshell change (modules/mango/quickshell/*.qml) working on the real screen before calling it done — run the working tree as a throwaway second instance, open popups and detail pages over IPC, take screenshots with grim and record animations with wf-recorder, then read the images. Use after editing the rail, its popups, the picker, OSD or notifications, or when asked to screenshot, record or visually check Quickshell.
---

# Verify Quickshell changes visually

Lint and the load check (`modules/mango/quickshell.nix`) only prove the QML
parses. Look at it too: run the working tree as a second instance next to
the user's live rail, drive it over IPC, capture, and Read the images.

## Run the working tree

The deployed config (`~/.config/quickshell/mango`) holds the generated
`Config.qml`, so overlay the edited files onto a copy of it:

```bash
S=<scratchpad>
rm -rf $S/qs && mkdir $S/qs
cp -L ~/.config/quickshell/mango/*.qml $S/qs/ && chmod u+w $S/qs/*
cp modules/mango/quickshell/*.qml $S/qs/ && cp ~/.config/quickshell/mango/Config.qml $S/qs/
cd $S
export XDG_RUNTIME_DIR=$(mktemp -d /tmp/qs.XXXX) WAYLAND_DISPLAY=/run/user/1000/wayland-0
timeout 60 quickshell -p qs/shell.qml > qs.log 2>&1 & P=$!
sleep 4
Q="quickshell ipc -p qs/shell.qml call"
# ... drive and capture ...
kill $P; rm -rf $XDG_RUNTIME_DIR
```

Why each part:

- **Private `XDG_RUNTIME_DIR`**: the sandbox cannot write
  `/run/user/1000/quickshell`, so without it the instance gets no IPC socket.
  Keep it short (`/tmp/qs.XXXX`): a scratchpad path pushes `ipc.sock` past
  the 108-byte Unix socket limit (`Failed to start IPC server`).
- **Absolute `WAYLAND_DISPLAY`**: the socket is no longer under the
  overridden runtime dir.
- **`kill $P`, never `pkill -f "quickshell -p ..."`**: the pattern matches
  the Bash tool's own command line and kills it (exit 143).
- The test rail draws over the live one; the user's own bar is untouched.
  No D-Bus or PipeWire in the sandbox, so tray icons, KDE Connect and audio
  state are missing or default. Ignore those log lines.

## Drive it

`shell.qml` lists the IPC targets. For verification prefer the idempotent ones:

```bash
$Q shell open controls wifi    # target, detail page ("" = tiles)
$Q shell open calendar ""
$Q shell openTarget            # what is open now
$Q shell close
$Q shell tray true
$Q osd volumeUp
```

Opening over IPC first asks `mmsg` for the cursor's monitor, so wait about
1 s before capturing. Anything reachable only by click or hover needs an
IPC call added first; the user cannot click for you.

## Capture

Neither tool is installed; run them through `nix-shell`.

Screenshot, then Read the PNG:

```bash
nix-shell -p grim --run 'grim shot.png'
```

Animation: record, extract frames, tile them into one contact sheet, and Read
that. You cannot watch video. `wf-recorder` writes frames only on damage, so
`fps=` resamples to an even rate; crop to the area that moves.

```bash
nix-shell -p wf-recorder ffmpeg --run "
  wf-recorder -y -f anim.mp4 >/dev/null 2>&1 & R=\$!; sleep 0.5
  $Q shell open calendar ''; sleep 1; $Q shell close; sleep 0.6
  kill -INT \$R; wait \$R
  ffmpeg -loglevel error -y -i anim.mp4 \
    -vf 'fps=10,crop=iw/2:ih/3:iw/4:0,scale=320:-1,tile=4x6' -frames:v 1 sheet.png"
```

## Finish

- Grep the log for warnings from the files you touched:
  `sed 's/\x1b\[[0-9;]*m//g' qs.log | grep -E '^ *(WARN|ERROR)' | grep '\.qml'`
- Captures show the user's whole screen. Keep them in the scratchpad and do
  not publish or send them anywhere unless asked.
