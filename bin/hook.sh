#!/usr/bin/env bash
# Hook entry point: plays a tone for a Claude Code lifecycle event.
#   hook.sh action-complete | input-required | system-failed | ...
#
# Reads the hook's JSON payload on stdin (and ignores it, except to stay quiet
# on nested stop-hook invocations). ALWAYS exits 0 — a notification sound must
# never block or fail a session.
#
# Silence it any time with:  touch ~/.claude/audio_notifications/.muted

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TONE="${1:-}"
MARK="${TMPDIR:-/tmp}/.claude-tone-last"
GAP=${TONE_MIN_GAP:-3}      # seconds; suppress a second tone right after the first

exec 2>/dev/null

# global mute
[ -f "$DIR/.muted" ] && exit 0

payload="$(cat 2>/dev/null || true)"

# don't chime for a Stop that was itself triggered by a stop hook continuation
case "$payload" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

# de-dupe: if any tone played within GAP seconds, stay quiet. Stops the
# "Claude asked a question" case from firing both a question and a done tone.
now=$(date +%s)
if [ -f "$MARK" ]; then
  last=$(cat "$MARK" 2>/dev/null || echo 0)
  [ $(( now - last )) -lt "$GAP" ] && exit 0
fi
echo "$now" > "$MARK"

"$DIR/play.sh" "$TONE" &
exit 0
