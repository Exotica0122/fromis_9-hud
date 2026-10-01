#!/usr/bin/env bash
# Smoke test: asserts the decisions notify-stop makes, using a stub HUD so nothing
# is drawn on screen. Run after a pull or before trusting a new machine.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0

# Whichever backend this platform actually uses; they take the same flags.
if [[ $(uname) == Linux ]]; then HUD=$here/bin/claude-hud-gtk
else HUD=$here/bin/claude-hud; fi

ok()   { printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL  %s\n     %s\n' "$1" "$2"; fail=$((fail+1)); }
note() { printf '  --    %s\n' "$1"; }
check() { [[ $2 == *"$3"* ]] && ok "$1" || bad "$1" "expected to contain: $3"; }
absent() { [[ $2 != *"$3"* ]] && ok "$1" || bad "$1" "should not contain: $3"; }

# Stub stands in for the HUD and records the arguments it was handed.
cat > "$tmp/stub" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$CLAUDE_TEST_ARGS"
STUB
chmod +x "$tmp/stub"
export CLAUDE_HUD_BIN="$tmp/stub" CLAUDE_TEST_ARGS="$tmp/args"

payload() { printf '{"hook_event_name":"%s","cwd":"%s"%s}' "$1" "$PWD" "${2:-}"; }
run() {
  : > "$CLAUDE_TEST_ARGS"
  printf '%s' "$1" | env "${@:2}" "$here/notify-stop" >"$tmp/out" 2>&1
  # notify-stop detaches the HUD, so its arguments land a moment after it exits.
  # A spin loop raced under load; wait on the file with a real 50ms tick instead.
  local i=0
  while [[ ! -s $CLAUDE_TEST_ARGS && $i -lt 60 ]]; do
    perl -e 'select(undef, undef, undef, 0.05)' 2>/dev/null || true
    i=$((i+1))
  done
  cat "$CLAUDE_TEST_ARGS"
}

echo "notify-stop"
args=$(run "$(payload Stop)" CLAUDE_NOTIFY_ALWAYS=1)
check "a finished turn renders a card"        "$args" "--title"
check "carries the tmux pane address"         "$args" "--badge"
if [[ -n ${TMUX_PANE:-} ]]; then
  check "click jumps to the pane"             "$args" "--on-click"
else
  note "skipped: no tmux pane, so there is no click target"
fi
absent "no blocked styling on a normal turn"  "$args" "#96000E"

args=$(run "$(payload Notification ',"matcher":"permission_prompt"')" CLAUDE_NOTIFY_ALWAYS=1)
check "a blocked session drops the portrait"  "$args" "--avatar none"
check "and turns red"                         "$args" "#96000E"
check "body derived from the event type"      "$args" "Needs your permission"

args=$(run "$(payload Notification ',"message":"Claude needs permission to run: ls"')" CLAUDE_NOTIFY_ALWAYS=1)
check "a message field wins over the type"    "$args" "permission to run: ls"

echo "privacy"
out=$(printf '%s' "$(payload Stop)" | CLAUDE_NOTIFY_ALWAYS=1 CLAUDE_NOTIFY_DEBUG=1 "$here/notify-stop" 2>&1)
absent "banner withholds the message body"    "$out" "banner=[Turn complete"
check  "banner still names the session"       "$out" "banner=[Finished"

echo "skip when you are watching"
# session_attached matters as much as the two active flags: in a detached session
# nobody is watching the pane, so notify-stop is right to render and the check
# would fail for the wrong reason.
onscreen=$([[ -n ${TMUX_PANE:-} ]] \
  && tmux display-message -p -t "$TMUX_PANE" \
       '#{pane_active}#{window_active}#{?session_attached,1,0}' 2>/dev/null)
if [[ $onscreen == 111 ]]; then
  if [[ $(uname) == Darwin ]]; then
    front=$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
      | sed -E 's/.*"LSDisplayName"="([^"]*)".*/\1/')
  elif command -v hyprctl >/dev/null 2>&1; then
    front=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')
  elif command -v swaymsg >/dev/null 2>&1; then
    front=$(swaymsg -t get_tree 2>/dev/null \
      | jq -r '.. | select(.focused? == true) | .app_id // empty' | head -1)
  fi
  args=$(run "$(payload Stop)" CLAUDE_TERMINAL_APP="$front" CLAUDE_NOTIFY_SKIP_FULLSCREEN=0)
  if [[ -z $front ]]; then
    note "skipped: no frontmost-window query on this compositor"
  else
  [[ -z $args ]] && ok "silent while you watch the pane" || bad "silent while you watch the pane" "rendered anyway"
  args=$(run "$(payload Stop)" CLAUDE_TERMINAL_APP=NoSuchApp CLAUDE_NOTIFY_SKIP_FULLSCREEN=0)
  [[ -n $args ]] && ok "renders when you are elsewhere" || bad "renders when you are elsewhere" "stayed silent"
  fi
else
  note "skipped: this pane is not on screen in an attached session"
fi

echo "fullscreen defers the turn"
# Stub compositor and notification daemon rather than the real ones: the suite must
# assert the same thing whatever is fullscreen, and whatever mode mako is in, while
# it runs. Both are stubbed throughout so neither rule can mask the other.
fake=$tmp/fake; mkdir -p "$fake"
hypr_stub() {                  # hypr_stub <fullscreen-mode>
  cat > "$fake/hyprctl" <<STUB
#!/usr/bin/env bash
echo '{"class":"someapp","fullscreen":$1}'
STUB
  chmod +x "$fake/hyprctl"
}
mako_stub() {                  # mako_stub <mode>
  cat > "$fake/makoctl" <<STUB
#!/usr/bin/env bash
[[ \$1 == mode ]] && echo '$1'
exit 0
STUB
  chmod +x "$fake/makoctl"
}
omarchy_stub() {               # omarchy_stub <on|off> <true|false>
  cat > "$fake/omarchy-shell" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "notifications isDnd") echo '$1' ;;
  "lock isLocked")       echo '$2' ;;
esac
STUB
  chmod +x "$fake/omarchy-shell"
}
# The shared stub truncates; replaying a batch needs every call kept.
cat > "$tmp/stub-many" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_TEST_ARGS"
STUB
chmod +x "$tmp/stub-many"

if [[ $(uname) == Linux ]]; then
  queue=$tmp/deferred.jsonl
  # MAX_WAIT keeps the watchers these assertions spawn from outliving the suite;
  # the replay case below gets its own queue, and so its own lock and watcher.
  defer_env=(PATH="$fake:$PATH" CLAUDE_NOTIFY_DEFER_QUEUE="$queue"
             CLAUDE_NOTIFY_DEFER_POLL=1 CLAUDE_NOTIFY_DEFER_MAX_WAIT=30
             CLAUDE_NOTIFY_NATIVE=0)
  # These assertions only care about the decision, not the replay. Draining the
  # queue after each one retires the watcher it spawned — left running, it would
  # flush into the shared stub the moment a later case stops being fullscreen, and
  # that case would read the stale card as its own.
  drain() { : > "$queue"; }
  mako_stub default
  omarchy_stub off false

  hypr_stub 2
  args=$(run "$(payload Stop)" "${defer_env[@]}")
  [[ -z $args ]] && ok "a fullscreen window defers the card" \
                 || bad "a fullscreen window defers the card" "rendered anyway"
  [[ -s $queue ]] && ok "and parks the turn in the queue" \
                  || bad "and parks the turn in the queue" "nothing queued"
  drain

  # mako draws on the overlay layer too, so a banner lands over the game just as
  # the card would. Deferring has to mean both or it has not helped.
  out=$(printf '%s' "$(payload Stop)" \
    | env PATH="$fake:$PATH" CLAUDE_NOTIFY_DEFER_QUEUE="$queue" \
          CLAUDE_NOTIFY_DEBUG=1 "$here/notify-stop" 2>&1 >/dev/null)
  absent "and holds the banner back with it"  "$out" "banner=["
  check  "saying it was queued"               "$out" "queued for later"
  drain

  hypr_stub 1
  args=$(run "$(payload Stop)" "${defer_env[@]}")
  [[ -n $args ]] && ok "a merely maximized window does not" \
                 || bad "a merely maximized window does not" "stayed silent"

  hypr_stub 3                  # maximized|fullscreen, the bitmask case
  args=$(run "$(payload Stop)" "${defer_env[@]}")
  [[ -z $args ]] && ok "maximized|fullscreen still counts as fullscreen" \
                 || bad "maximized|fullscreen still counts as fullscreen" "rendered anyway"
  drain

  hypr_stub 2
  args=$(run "$(payload Stop)" "${defer_env[@]}" CLAUDE_NOTIFY_ALWAYS=1)
  [[ -n $args ]] && ok "CLAUDE_NOTIFY_ALWAYS overrides it" \
                 || bad "CLAUDE_NOTIFY_ALWAYS overrides it" "stayed silent"
  args=$(run "$(payload Stop)" "${defer_env[@]}" CLAUDE_NOTIFY_SKIP_FULLSCREEN=0)
  [[ -n $args ]] && ok "CLAUDE_NOTIFY_SKIP_FULLSCREEN=0 turns it off" \
                 || bad "CLAUDE_NOTIFY_SKIP_FULLSCREEN=0 turns it off" "stayed silent"

  echo "and replays it afterwards"
  # Three turns pile up behind a fullscreen window, then the window goes away. Its
  # own queue path, so it gets its own lock and a watcher carrying this stub rather
  # than inheriting one left polling by the assertions above.
  rq=$tmp/replay-queue.jsonl
  replay=$tmp/replay; : > "$replay"
  replay_env=(PATH="$fake:$PATH" CLAUDE_NOTIFY_DEFER_QUEUE="$rq"
              CLAUDE_NOTIFY_DEFER_POLL=1 CLAUDE_NOTIFY_DEFER_MAX_WAIT=60
              CLAUDE_NOTIFY_NATIVE=0
              CLAUDE_HUD_BIN="$tmp/stub-many" CLAUDE_TEST_ARGS="$replay")
  hypr_stub 2
  for pane in alpha beta gamma; do
    printf '%s' "$(payload Stop)" \
      | env "${replay_env[@]}" CLAUDE_NOTIFY_MEMBER="$pane" \
            "$here/notify-stop" >/dev/null 2>&1
  done
  queued=$(wc -l <"$rq" 2>/dev/null || echo 0)
  [[ $queued -eq 3 ]] && ok "three turns queue up, none shown" \
                      || bad "three turns queue up, none shown" "queued=$queued shown=$(wc -l <"$replay")"

  hypr_stub 0                  # the game closes
  for _ in $(seq 1 20); do
    [[ $(wc -l <"$replay" 2>/dev/null || echo 0) -ge 3 ]] && break
    sleep 1
  done
  shown=$(wc -l <"$replay" 2>/dev/null || echo 0)
  [[ $shown -eq 3 ]] && ok "all three replay once it is gone" \
                     || bad "all three replay once it is gone" "only $shown replayed"
  order=$(grep -oE -- '--member [a-z]+' "$replay" | awk '{print $2}' | tr '\n' ' ')
  [[ $order == "alpha beta gamma " ]] && ok "oldest first, so the newest lands on top" \
                                      || bad "oldest first, so the newest lands on top" "got: $order"
  chimes=$(( $(grep -c . "$replay") - $(grep -c -- '--sound none' "$replay") ))
  [[ $chimes -eq 1 ]] && ok "one chime for the batch, not one per turn" \
                      || bad "one chime for the batch, not one per turn" "$chimes cards would chime"
  [[ ! -s $rq ]] && ok "the queue is drained" \
                 || bad "the queue is drained" "$(wc -l <"$rq") left behind"
  rm -f "$fake/hyprctl" "$fake/makoctl" "$fake/omarchy-shell" "$queue" "$rq"
  rmdir "$queue.lock" "$rq.lock" 2>/dev/null       # mkdir is the lock, so rm -f will not do
else
  note "skipped: deferral has no macOS probe yet"
fi

echo "do-not-disturb"
if [[ $(uname) == Linux ]]; then
  hypr_stub 0                  # pin the other rule off, so this one is what is tested
  omarchy_stub off false
  mako_stub do-not-disturb
  args=$(run "$(payload Stop)" PATH="$fake:$PATH" CLAUDE_NOTIFY_NATIVE=0)
  [[ -z $args ]] && ok "do-not-disturb suppresses the card" \
                 || bad "do-not-disturb suppresses the card" "rendered anyway"

  out=$(printf '%s' "$(payload Stop)" \
    | env PATH="$fake:$PATH" CLAUDE_NOTIFY_DEBUG=1 "$here/notify-stop" 2>&1 >/dev/null)
  check "and still records it in a banner"   "$out" "banner=["
  check "saying why it went quiet"           "$out" "do-not-disturb"

  mako_stub default
  args=$(run "$(payload Stop)" PATH="$fake:$PATH" CLAUDE_NOTIFY_NATIVE=0)
  [[ -n $args ]] && ok "the default mode does not" \
                 || bad "the default mode does not" "stayed silent"

  mako_stub do-not-disturb
  args=$(run "$(payload Stop)" PATH="$fake:$PATH" CLAUDE_NOTIFY_NATIVE=0 CLAUDE_NOTIFY_SKIP_DND=0)
  [[ -n $args ]] && ok "CLAUDE_NOTIFY_SKIP_DND=0 turns it off" \
                 || bad "CLAUDE_NOTIFY_SKIP_DND=0 turns it off" "stayed silent"

  args=$(run "$(payload Stop)" PATH="$fake:$PATH" CLAUDE_NOTIFY_NATIVE=0 CLAUDE_NOTIFY_ALWAYS=1)
  [[ -n $args ]] && ok "CLAUDE_NOTIFY_ALWAYS overrides it" \
                 || bad "CLAUDE_NOTIFY_ALWAYS overrides it" "stayed silent"

  # mako modes are arbitrary strings, so the one we match on has to be settable.
  mako_stub quiet-please
  args=$(run "$(payload Stop)" PATH="$fake:$PATH" CLAUDE_NOTIFY_NATIVE=0)
  [[ -n $args ]] && ok "an unrelated mode is not do-not-disturb" \
                 || bad "an unrelated mode is not do-not-disturb" "stayed silent"
  args=$(run "$(payload Stop)" PATH="$fake:$PATH" CLAUDE_NOTIFY_NATIVE=0 CLAUDE_NOTIFY_DND_MODE=quiet-please)
  [[ -z $args ]] && ok "CLAUDE_NOTIFY_DND_MODE matches a custom mode" \
                 || bad "CLAUDE_NOTIFY_DND_MODE matches a custom mode" "rendered anyway"

  mako_stub default
  omarchy_stub on false
  args=$(run "$(payload Stop)" PATH="$fake:$PATH" CLAUDE_NOTIFY_NATIVE=0)
  [[ -z $args ]] && ok "the Omarchy shell's do-not-disturb suppresses the card" \
                 || bad "the Omarchy shell's do-not-disturb suppresses the card" "rendered anyway"
  omarchy_stub off false
  args=$(run "$(payload Stop)" PATH="$fake:$PATH" CLAUDE_NOTIFY_NATIVE=0)
  [[ -n $args ]] && ok "and its off state does not" \
                 || bad "and its off state does not" "stayed silent"

  echo "a locked screen is not watching"
  watch=$tmp/watch; mkdir -p "$watch"
  cat > "$watch/tmux" <<'STUB'
#!/usr/bin/env bash
case "$*" in *pane_active*) echo "1 1 1" ;; *) echo "test:1.1" ;; esac
STUB
  chmod +x "$watch/tmux"
  watch_env=(PATH="$watch:$fake:$PATH" TMUX_PANE=%0 CLAUDE_TERMINAL_APP=someapp
             CLAUDE_NOTIFY_NATIVE=0)
  args=$(run "$(payload Stop)" "${watch_env[@]}")
  [[ -z $args ]] && ok "an unlocked Omarchy shell stays silent on the watched pane" \
                 || bad "an unlocked Omarchy shell stays silent on the watched pane" "rendered anyway"
  omarchy_stub off true
  args=$(run "$(payload Stop)" "${watch_env[@]}")
  [[ -n $args ]] && ok "a locked Omarchy shell still notifies" \
                 || bad "a locked Omarchy shell still notifies" "stayed silent"

  rm -f "$fake/hyprctl" "$fake/makoctl" "$fake/omarchy-shell"
else
  note "skipped: no macOS do-not-disturb probe"
fi

echo "hud binary"
"$HUD" --preview "$tmp/p.png" --title t --body b >/dev/null 2>&1
[[ -s $tmp/p.png ]] && ok "renders a card offscreen" || bad "renders a card offscreen" "no png produced"
# Only the Swift backend is compiled, so only it can go stale. stat -f is BSD-only,
# which is fine: this whole block is macOS.
if [[ $(uname) == Darwin ]] && command -v swiftc >/dev/null 2>&1; then
  # Backdate the binary rather than touching the source: /bin/bash 3.2, which CI uses,
  # compares -nt at whole-second granularity, so a same-second touch does not read as newer.
  touch -t 202001010000 "$here/bin/claude-hud"
  before=$(stat -f %m "$here/bin/claude-hud")
  printf '%s' "$(payload Stop)" \
    | env -u CLAUDE_HUD_BIN CLAUDE_NOTIFY_ALWAYS=1 CLAUDE_NOTIFY_SECONDS=1 CLAUDE_NOTIFY_SOUND=none \
      "$here/notify-stop" >/dev/null 2>&1
  after=$(stat -f %m "$here/bin/claude-hud")
  if [[ $after -gt $before ]]; then
    ok "rebuilds when the source is newer"
  else
    why=$(printf '%s' "$(payload Stop)" \
      | env -u CLAUDE_HUD_BIN CLAUDE_NOTIFY_ALWAYS=1 CLAUDE_NOTIFY_SECONDS=1 \
        CLAUDE_NOTIFY_SOUND=none CLAUDE_NOTIFY_DEBUG=1 "$here/notify-stop" 2>&1 >/dev/null \
      | grep 'rebuild skipped' | head -1)
    bad "rebuilds when the source is newer" "mtime unchanged (${why:-no reason reported}); \
swiftc=$(command -v swiftc || echo absent) TMPDIR=${TMPDIR:-unset} src=$(stat -f %m "$here/bin/claude-hud.swift") bin=$after"
  fi
fi

echo "paths and roster"
args=$(run "$(payload Stop)" CLAUDE_NOTIFY_ALWAYS=1)
if [[ -n ${TMUX_PANE:-} ]]; then
  check "resolves its siblings from the checkout" "$args" "$here/focus-pane"
else
  note "skipped: the sibling path only appears on --on-click, which needs a pane"
fi
absent "no leftover ~/.claude/hooks path"        "$args" ".claude/hooks"

conf=$tmp/portraits; mkdir -p "$conf"
printf '%s\n' '# <slug> <display name> <rail hex>' 'solo Solo One 00FF00' >"$conf/roster.conf"
render() {                     # render <out> <portraits-dir>
  CLAUDE_HUD_PORTRAITS=$2 "$HUD" --preview "$1" --member solo \
    --avatar none --sound none --title t --body b >/dev/null 2>&1
}
render "$tmp/roster.png" "$conf"
render "$tmp/fallback.png" "$tmp/no-such-dir"
if [[ -s $tmp/roster.png && -s $tmp/fallback.png ]]; then
  cmp -s "$tmp/roster.png" "$tmp/fallback.png" \
    && bad "roster.conf recolours the rail" "identical to the compiled fallback" \
    || ok "roster.conf recolours the rail"
  ok "renders with no portraits directory at all"
else
  bad "roster.conf recolours the rail" "a preview failed to render"
fi

echo "portrait lookup"
# Two distinct, definitely-valid images, rendered by the HUD itself.
# They must differ in the middle of the frame: the avatar crop is centred, so images
# differing only at an edge (an accent rail, say) survive the crop looking identical.
"$HUD" --preview "$tmp/A.png" --avatar none --sound none \
  --title "XXXXXXXXXXXXXXXXXXXX" --body "$(printf 'X%.0s' {1..120})" >/dev/null 2>&1
"$HUD" --preview "$tmp/B.png" --avatar none --sound none \
  --title "oooooooooooooooooooo" --body "$(printf 'o%.0s' {1..120})" >/dev/null 2>&1
pri=$tmp/primary; mkdir -p "$pri" "$here/portraits"
printf 'solo Solo One 00FF00\n' >"$pri/roster.conf"
cp "$tmp/A.png" "$pri/solo.png"
# .webp by name, PNG by content — both NSImage and GdkPixbuf sniff the bytes, and the
# point here is that a lower-priority directory holds the extension the lookup would
# otherwise prefer.
cp "$tmp/B.png" "$here/portraits/solo.webp"
shot() { CLAUDE_HUD_PORTRAITS=$pri "$HUD" --preview "$1" --member solo \
  --sound none --title t --body b >/dev/null 2>&1; }
shot "$tmp/both.png"
rm -f "$here/portraits/solo.webp"
shot "$tmp/alone.png"
if [[ -s $tmp/both.png && -s $tmp/alone.png ]]; then
  cmp -s "$tmp/both.png" "$tmp/alone.png" \
    && ok "a higher-priority directory beats a preferred extension below it" \
    || bad "a higher-priority directory beats a preferred extension below it" \
           "the checkout's .webp won over \$CLAUDE_HUD_PORTRAITS/.png"
else
  bad "a higher-priority directory beats a preferred extension below it" "a preview failed"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
