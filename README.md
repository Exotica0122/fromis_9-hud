# fromis9-hud

A HUD that appears top-centre when a Claude Code turn finishes: session name, tmux pane
address, repo, branch, and a snippet of the last reply, over a pink fromis_9 theme with a
member portrait. Clicking it jumps to the tmux pane that fired it.

Notifications stack rather than overlap — collapsed, only the newest is readable with the
rest peeking beneath; hovering fans them out and holds every clock until the pointer
leaves. A session that is *blocked* rather than finished looks structurally different: no
portrait, a deep-red rail and its own glyph, so it cannot be misread as "done".

macOS only — the HUD is AppKit.

## Portraits are not included

**This repository ships no member photos.** They are third-party images and not mine to
redistribute. Without them the HUD falls back to a coloured rail per member and works
exactly the same — adding them is optional.

### 1. Put the file where the HUD looks

Name each file for its slug and drop it in `~/.claude/portraits/`:

```
~/.claude/portraits/
  hayoung.webp   jiwon.png   chaeyoung.jpg   nagyung.webp   jiheon.heic
```

`.webp`, `.png`, `.jpg`, `.jpeg` and `.heic` all load, and the extension does not have to
match between members. The lookup order is `$CLAUDE_HUD_PORTRAITS`, then
`~/.claude/portraits`, then `portraits/` beside this checkout — per file, so you can keep
most of the set in one place and override one member from another.

### 2. Crop the image

The portrait is drawn in an 84×84pt rounded square, so the HUD cuts a **square** out of
whatever you give it. Cropping it yourself first is the predictable way to control what
ends up on screen.

**Crop to these specs:**

| Property | Requirement |
|---|---|
| shape | square, 1:1 |
| size | **512×512px** recommended; **168×168px** is the practical minimum (84pt at 2× on a Retina display) |
| framing | face centred, head filling roughly three-quarters of the frame, a little headroom above |
| format | `.webp`, `.png`, `.jpg`, `.jpeg` or `.heic` |

Do **not** round the corners, add a border, or add transparency — the HUD applies a 12pt
corner radius and a 2.5pt coloured border itself, and anything you bake in will show
through as a double edge.

Then tell the HUD to use your square as-is, by adding one line per image to
`~/.claude/portraits/crops.conf`:

```
# <slug> <focus> <zoom>
jiwon 0.5 1
```

Without that line the HUD assumes an uncropped photo and crops in further (see below).

macOS can do this without extra tools. **Preview** is the reliable route when the face is
not dead centre: hold <kbd>shift</kbd> to drag a square selection over the face, **Tools →
Crop**, then **Tools → Adjust Size** to 512×512.

From the terminal, `sips` squares off the photo and resizes it in two steps:

```bash
sips -c 1000 1000 source.jpg --out /tmp/square.png        # centre crop to a square
sips -z 512 512 /tmp/square.png --out ~/.claude/portraits/jiwon.png
```

Pass your source's **shorter edge** to `-c` (1000 for a 1000×1250 photo). Note that `-c`
crops from the centre, so on a typical head-and-shoulders portrait it lands on the torso —
frame it in Preview first and then run only the `-z` line. `sips` reads `.webp` fine but
will not write it; output `.png` instead.

### 3. Or drop in an uncropped portrait

If you would rather not crop anything, the defaults are tuned for a **4:5 portrait photo**
— 1000×1250px is the reference shape — with the face in the upper third, which is the
usual head-and-shoulders press or profile shot.

With no `crops.conf` line, the HUD takes a square **59% of the shorter edge** (focus
`0.30`, zoom `1.7`), horizontally centred, positioned 30% of the way down. Two things
follow from that:

- **The crop is always horizontally centred and cannot be panned.** If the face sits left
  or right of centre, no setting will fix it — crop the image yourself as in step 2.
- **Only 59% of the short edge survives**, so the source needs at least **300px on its
  shorter edge** to still land above 168px.

When a photo is framed differently, tune the two numbers rather than re-cropping:

| Setting | What it controls |
|---|---|
| `focus` | where the **centre** of the crop sits vertically: `0` = top edge, `1` = bottom edge. Lower it for a face high in the frame. Clamped so the crop never leaves the image. |
| `zoom` | how tight the crop is. `1` uses the largest square that fits; `1.7` is the default; higher crops in further; below `1` is treated as `1`. |

Check a pair by eye without waiting for a turn to end — this renders the card to a PNG
instead of the screen:

```bash
bin/claude-hud --preview /tmp/try.png --member chaeyoung \
  --avatar-focus 0.02 --avatar-zoom 1.45 \
  --title "✳ crop check" --badge "session:1.1" --repo repo --branch main --body "..."
open /tmp/try.png
```

Those two flags override `crops.conf` for that one render, so when it looks right, copy
the numbers into the file as a `<slug> <focus> <zoom>` line.

### 4. Members the HUD does not know about

Slugs, display names and the rail colour used when no photo is present come from
`~/.claude/portraits/roster.conf`, which `install.sh` seeds and you can edit without a
rebuild:

```
# <slug> <display name> <rail hex>
hayoung    Hayoung    8F3400
jiwon      Jiwon      07496F
```

Add a row to add a member, delete one to drop her from the rotation, change the hex to
retune a rail. The file replaces the built-in cast entirely, so list everyone you want.
Delete the file to fall back to the five compiled into the binary. A member with a row but
no image file is fine — she gets the rail.

To check which member a slug resolves to, render it: `--member <slug>`.

## Install

```bash
git clone https://github.com/Exotica0122/fromis9-hud
cd fromis9-hud && ./install.sh
```

It checks dependencies, compiles the Swift binary, seeds `~/.claude/portraits`, links the
checkout at `~/.claude/fromis9-hud`, and runs a smoke test. It does **not** edit your
`settings.json` — it prints `hooks.example.json` for you to merge:

```json
"Stop": [{ "hooks": [{ "type": "command",
  "command": "~/.claude/fromis9-hud/notify-stop", "timeout": 10, "async": true }] }]
```

The compiled binary is deliberately not committed — it is architecture-specific and
rebuilds in about a second. `notify-stop` also rebuilds it automatically when the source
is newer, swapping it in only on a successful compile.

Run `./test.sh` after a pull or on a new machine. It points the hook at a stub via
`CLAUDE_HUD_BIN` and asserts on the arguments, so nothing is drawn on screen, and it
exits non-zero on failure.

## Dependencies

| Dependency | Required? |
|---|---|
| macOS | required — the HUD is AppKit |
| `swiftc` | required — `xcode-select --install` |
| `jq` | required — reads the hook payload and transcript |
| `tmux` | optional — without it there is no pane address and no click-to-focus |
| `terminal-notifier` | optional — makes the Notification Center banner clickable |

## How it runs

One daemon owns the panel and renders every notification; the hook is a client that posts
its arguments over a Unix socket in `TMPDIR` and exits immediately. The daemon starts on
the first notification and exits after 45 seconds with nothing to show. If it cannot be
reached the hook falls back to `--solo`, a standalone one-shot stack, so a wedged daemon
never costs a notification.

The hook stays silent when you are already looking at the pane — it is on screen in an
attached session, the terminal is frontmost, and the screen is not locked. Set
`CLAUDE_NOTIFY_ALWAYS=1` to notify regardless.

## Files

| File | Purpose |
|---|---|
| `notify-stop` | the Stop/Notification hook: builds the notification from the transcript |
| `bin/claude-hud.swift` | the HUD, the only real source file |
| `focus-pane` | jumps to a tmux pane and raises the terminal |
| `hooks.example.json` | the snippet to merge into `settings.json` |
| `portraits.example/` | `roster.conf` and `crops.conf` templates — no images |
| `install.sh` | dependency check, build, symlink |
| `test.sh` | smoke test — 16 assertions, no windows drawn |

## Blocked notifications

`Notification` fires for twelve matcher values, most of which do not need you —
`auth_success` and the `quota_auto_resume_*` family among them. The example snippet
registers a matcher limited to the ones that do: `permission_prompt`, `idle_prompt`,
`agent_needs_input` and the two `elicitation` dialogs.

The field carrying the notification text is not documented, so the hook tries `.message`,
`.notification`, `.text`, `.title` and then derives a sentence from the event type, which
the matcher guarantees is one of the above. Set `CLAUDE_NOTIFY_CAPTURE=1` to append raw
payloads to `notification-payloads.jsonl` (last 40 kept) if you want to confirm the real
field name — it is off by default because a payload can quote a command.

## Tuning

```bash
CLAUDE_NOTIFY_SOUND=Hero      # system sound name, a file in ~/.claude/sounds, a path, or none
CLAUDE_NOTIFY_VOLUME=0.6      # 0.0 to 1.0
CLAUDE_NOTIFY_SECONDS=8       # how long the HUD holds
CLAUDE_NOTIFY_MEMBER=jiwon    # pin a member instead of picking at random
CLAUDE_NOTIFY_ACCENT='#f59e0b'
CLAUDE_NOTIFY_NATIVE=0        # skip the Notification Center banner
CLAUDE_TERMINAL_APP=Ghostty   # which app focus-pane raises
CLAUDE_HUD_PORTRAITS=~/pics   # where portraits and their config live
```

The Notification Center banner carries no message text. The HUD is transient and already
on your screen, but Notification Center keeps a history, and a turn that discussed a token
or a `.env` path would leave that text sitting outside the terminal. The banner shows the
session name, the pane address and whether the turn finished or is waiting on you.
`CLAUDE_NOTIFY_NATIVE_BODY=1` opts back in.

To see a change without waiting for a turn to end, render it offscreen:

```bash
bin/claude-hud --preview /tmp/try.png --preview-backdrop 202024 \
  --member nagyung --title "✳ test" --badge "session:4.1" \
  --repo repo --branch main --body "..."
```

### Which member appears

By default the portrait is seeded from the pane address and the calendar day, so a pane
keeps the same face all day and the cast rotates overnight. Panes within one tmux session
get different members, since the seed is the full address rather than the session name.

| `--member` | Behaviour |
|---|---|
| *(omitted)* | seeded from pane address + day (default) |
| `hash` | stable per tmux session, never rotates |
| `random` | a different member every notification |
| `<slug>` | always that member |

## Notification Center

`notify-stop` also posts a native banner via `terminal-notifier`, falling back to
`osascript`. This is best-effort: macOS refuses notification authorisation to ad-hoc
signed binaries and to processes spawned from a long-running tmux server, so on some
machines nothing appears. The HUD does not depend on it.

## tmux pane labels

Optional, and the one thing `install.sh` cannot do for you — it shows the session name per
pane so the HUD's badge matches what you see:

```tmux
set -g pane-border-status top
set -g pane-border-format ' #{?pane_active,#[fg=black bg=green bold],#[fg=green]} #{pane_index} #[default] #{?#{||:#{==:#{pane_title},},#{==:#{pane_title},#{host_short}}},#[fg=white]#{pane_current_command},#{pane_title}} '
set -g pane-border-style 'fg=brightblack'
set -g pane-active-border-style 'fg=green'
```

## Licence and attribution

Code is MIT — see `LICENSE`.

This is an unofficial fan project with no affiliation to, or endorsement by, fromis_9 or
its label. It ships no photos. `install.sh` optionally fetches the group's wordmark from
Wikimedia Commons, where it is tagged public domain as below the threshold of originality
(`PD-textlogo`); that covers copyright but not trademark, so if you redistribute or use
this commercially, that is yours to clear. Skip the fetch and the HUD renders without it.
