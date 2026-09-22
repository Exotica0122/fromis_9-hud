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
exactly the same.

To add your own, drop files named for the slug into `~/.claude/portraits/`:

```
hayoung  jiwon  chaeyoung  nagyung  jiheon
```

`.webp`, `.png`, `.jpg` and `.heic` all load. If a face sits off-centre, add a line to
`~/.claude/portraits/crops.conf`:

```
# <slug> <focus 0=top..1=bottom> <zoom >1 tightens>
chaeyoung 0.02 1.45
```

The slugs, and the rail colour used when a portrait is missing, come from
`~/.claude/portraits/roster.conf` — seeded by `install.sh` and editable without a rebuild:

```
# <slug> <display name> <rail hex>
hayoung    Hayoung    8F3400
jiwon      Jiwon      07496F
```

Delete that file to fall back to the cast compiled into the binary. Portraits and their
config are looked up in order: `$CLAUDE_HUD_PORTRAITS`, then `~/.claude/portraits`, then
`portraits/` beside this checkout.

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

| | |
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

| | |
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

| `--member` | behaviour |
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
