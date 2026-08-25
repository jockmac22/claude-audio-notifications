#!/usr/bin/env bash
# Play a notification tone by name.
#   play.sh action-complete | input-required | in-process | action-failed | system-failed
# "in-process" is rate-limited (TONE_THROTTLE seconds, default 30) so a long
# run can't turn into a drum solo.
#
# Tone directory resolution, first hit wins:
#   $CLAUDE_TONES  ->  ~/.claude/audio_notifications  ->  this script's dir  ->  ../tones/wav
# The last one lets the script run straight from a repo checkout.

set -u

case "${1:-}" in
  action-complete) f=positive_action-complete ;;
  input-required)  f=positive_input-required ;;
  in-process)      f=positive_in-process ;;
  action-failed)   f=negative_action-failed ;;
  system-failed)   f=negative_system-failed ;;
  *) echo "usage: $(basename "$0") {action-complete|input-required|in-process|action-failed|system-failed}" >&2
     exit 64 ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for d in "${CLAUDE_TONES:-}" \
         "$HOME/.claude/audio_notifications" \
         "$HERE" \
         "$HERE/../tones/wav"; do
  [ -n "$d" ] || continue
  if [ -f "$d/$f.wav" ]; then TONES="$d"; break; fi
done
if [ -z "${TONES:-}" ]; then
  echo "no tone directory found (set CLAUDE_TONES to override)" >&2
  exit 66
fi

# throttle the heartbeat tone
if [ "$f" = "positive_in-process" ]; then
  THROTTLE=${TONE_THROTTLE:-30}
  stamp="${TMPDIR:-/tmp}/.claude-tone-in-process"
  now=$(date +%s)
  if [ -f "$stamp" ] && [ $(( now - $(cat "$stamp" 2>/dev/null || echo 0) )) -lt "$THROTTLE" ]; then
    exit 0
  fi
  echo "$now" > "$stamp"
fi

# afplay is macOS. Fall back to whatever the platform has, then give up quietly:
# a missing audio player must never be reported as a task failure.
for player in afplay paplay aplay ffplay; do
  if command -v "$player" >/dev/null 2>&1; then
    case "$player" in
      ffplay) exec ffplay -nodisp -autoexit -loglevel quiet "$TONES/$f.wav" ;;
      *)      exec "$player" "$TONES/$f.wav" ;;
    esac
  fi
done
echo "no audio player found (afplay/paplay/aplay/ffplay) — skipping tone" >&2
exit 0
