#!/usr/bin/env bash
# Smoke test: asserts the decisions notify-stop makes, using a stub HUD so nothing
# is drawn on screen. Run after a pull or before trusting a new machine.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0

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
check "click jumps to the pane"               "$args" "--on-click"
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
onscreen=$(tmux display-message -p -t "${TMUX_PANE:-}" '#{pane_active}#{window_active}' 2>/dev/null)
if [[ $onscreen == 11 ]]; then
  front=$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null \
    | sed -E 's/.*"LSDisplayName"="([^"]*)".*/\1/')
  args=$(run "$(payload Stop)" CLAUDE_TERMINAL_APP="$front")
  [[ -z $args ]] && ok "silent while you watch the pane" || bad "silent while you watch the pane" "rendered anyway"
  args=$(run "$(payload Stop)" CLAUDE_TERMINAL_APP=NoSuchApp)
  [[ -n $args ]] && ok "renders when you are elsewhere" || bad "renders when you are elsewhere" "stayed silent"
else
  note "skipped: this pane is not on screen, so the check cannot be exercised"
fi

echo "hud binary"
"$here/bin/claude-hud" --preview "$tmp/p.png" --title t --body b >/dev/null 2>&1
[[ -s $tmp/p.png ]] && ok "renders a card offscreen" || bad "renders a card offscreen" "no png produced"
if command -v swiftc >/dev/null 2>&1; then
  before=$(stat -f %m "$here/bin/claude-hud")
  touch "$here/bin/claude-hud.swift"
  printf '%s' "$(payload Stop)" \
    | env -u CLAUDE_HUD_BIN CLAUDE_NOTIFY_ALWAYS=1 CLAUDE_NOTIFY_SECONDS=1 CLAUDE_NOTIFY_SOUND=none \
      "$here/notify-stop" >/dev/null 2>&1
  after=$(stat -f %m "$here/bin/claude-hud")
  [[ $after -gt $before ]] && ok "rebuilds when the source is newer" \
    || bad "rebuilds when the source is newer" "binary mtime unchanged"
fi

echo "paths and roster"
args=$(run "$(payload Stop)" CLAUDE_NOTIFY_ALWAYS=1)
check  "resolves its siblings from the checkout" "$args" "$here/focus-pane"
absent "no leftover ~/.claude/hooks path"        "$args" ".claude/hooks"

conf=$tmp/portraits; mkdir -p "$conf"
printf '%s\n' '# <slug> <display name> <rail hex>' 'solo Solo One 00FF00' >"$conf/roster.conf"
render() {                     # render <out> <portraits-dir>
  CLAUDE_HUD_PORTRAITS=$2 "$here/bin/claude-hud" --preview "$1" --member solo \
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
