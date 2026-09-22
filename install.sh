#!/usr/bin/env bash
# Build and verify fromis9-hud on a new machine.
set -euo pipefail

# -P resolves through symlinks: invoked via ~/.claude/fromis9-hud this would otherwise
# report the link path and we would link it to itself.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
portraits=$HOME/.claude/portraits
ok=1

say() { printf '%s\n' "$*"; }
need() {
  if command -v "$1" >/dev/null 2>&1; then
    say "  ok       $1"
  else
    say "  MISSING  $1 — $2"; ok=0
  fi
}

say "checking dependencies"
[[ $(uname) == Darwin ]] || { say "  MISSING  macOS — this HUD is AppKit-only"; exit 1; }
need swiftc "xcode-select --install"
need jq "brew install jq"
need tmux "brew install tmux (optional: enables the pane address and click-to-focus)"
command -v terminal-notifier >/dev/null 2>&1 \
  && say "  ok       terminal-notifier" \
  || say "  absent   terminal-notifier — optional; without it the Notification Center banner falls back to osascript and is not clickable"
[[ $ok == 1 ]] || { say "install aborted"; exit 1; }

say "building claude-hud"
swiftc -O -o "$here/bin/claude-hud" "$here/bin/claude-hud.swift"
chmod +x "$here/notify-stop" "$here/focus-pane" "$here/bin/claude-hud"

say "portraits"
mkdir -p "$portraits"
for f in roster.conf crops.conf; do
  if [[ -e $portraits/$f ]]; then
    say "  ok       $f already in ~/.claude/portraits"
  else
    cp "$here/portraits.example/$f" "$portraits/$f"
    say "  seeded   $f → ~/.claude/portraits (edit to taste)"
  fi
done

# Copyright-clear (Commons PD-textlogo: below the threshold of originality), but still a
# trademark — fetched on request rather than committed, and the HUD renders without it.
if [[ ! -f $here/portraits/logo.svg ]]; then
  mkdir -p "$here/portraits"
  curl -fsS -m 20 -H 'User-Agent: fromis9-hud-install/1.0' \
    'https://upload.wikimedia.org/wikipedia/commons/8/8c/Fromis_9_logo_%28ICON%29.svg' \
    -o "$here/portraits/logo.svg" \
    && say "  fetched  logo.svg (public domain — see README on trademark)" \
    || say "  skipped  logo.svg — could not reach Wikimedia; the HUD renders without it"
fi

say "linking into ~/.claude"
# One level of symlink, resolved physically: stow writes relative links, so a literal
# readlink comparison would not recognise its work and would move it aside.
resolve() {                    # resolve <path> -> physical path
  local p=$1 d b t
  d=$(dirname "$p"); b=$(basename "$p")
  if [[ -L $p ]]; then
    t=$(readlink "$p"); [[ $t == /* ]] || t="$d/$t"
    d=$(dirname "$t"); b=$(basename "$t")
  fi
  d=$(cd -P "$d" 2>/dev/null && pwd -P) || return 1
  printf '%s\n' "${d%/}/$b"
}
link() {                       # link <target> <link-path>
  local target=$1 link=$2
  if [[ -L $link ]] && [[ $(resolve "$link" 2>/dev/null) == "$(resolve "$target")" ]]; then
    say "  ok       $(basename "$link") already points here"; return
  fi
  if [[ -e $link || -L $link ]]; then
    # Never delete what is already there.
    local backup="$link.replaced-$(date +%Y%m%d%H%M%S)"
    mv "$link" "$backup" || { say "  MISSING  could not move $link aside"; return; }
    say "  moved    existing $(basename "$link") → $(basename "$backup")"
  fi
  mkdir -p "$(dirname "$link")"
  ln -s "$target" "$link" && say "  linked   $(basename "$link") → $target"
}
link "$here" "$HOME/.claude/fromis9-hud"

say "smoke test"
"$here/bin/claude-hud" --preview "${TMPDIR:-/tmp}/fromis9-hud-smoke.png" \
  --title "install check" --badge "session:1.1" --repo repo --branch main \
  --body "If you can read this, the build works." >/dev/null
say "  ok       rendered ${TMPDIR:-/tmp}/fromis9-hud-smoke.png"

count=0
for dir in "$portraits" "$here/portraits"; do
  [[ -d $dir ]] || continue
  count=$((count + $(find "$dir" -maxdepth 1 \( -name '*.webp' -o -name '*.png' -o -name '*.jpg' -o -name '*.heic' \) \
    ! -name 'logo*' 2>/dev/null | wc -l | tr -d ' ')))
done
say "  info     $count portrait(s) found (0 is fine — falls back to a coloured rail)"

settings=$HOME/.claude/settings.json
if [[ -f $settings ]] && grep -q 'fromis9-hud/notify-stop' "$settings" 2>/dev/null; then
  say "  ok       hooks already registered in settings.json"
else
  cat <<SNIPPET

the hooks are NOT registered yet. Merge hooks.example.json into
$settings — it is your file and this script will not edit it:

$(cat "$here/hooks.example.json")
SNIPPET
fi

cat <<EOS

tmux pane labels are the one other thing this script does not install:

   in ~/.tmux.conf (optional, shows the session name per pane)

   set -g pane-border-status top
   set -g pane-border-format ' #{?pane_active,#[fg=black bg=green bold],#[fg=green]} #{pane_index} #[default] #{?#{||:#{==:#{pane_title},},#{==:#{pane_title},#{host_short}}},#[fg=white]#{pane_current_command},#{pane_title}} '
   set -g pane-border-style 'fg=brightblack'
   set -g pane-active-border-style 'fg=green'

done. test with:
  printf '{"cwd":"\$PWD"}' | $here/notify-stop
EOS
