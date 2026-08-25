#!/usr/bin/env bash
# Install the audio notification tones, helper scripts and skills into ~/.claude,
# and allowlist playback so Claude never has to ask before making a sound.
#
#   ./install.sh              install / refresh
#   ./install.sh --with-hooks also wire the Stop / Notification lifecycle hooks
#
# Idempotent: safe to re-run. Backs up settings.json before touching it.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DEST="$CLAUDE_DIR/audio_notifications"
SKILLS="$CLAUDE_DIR/skills"
SETTINGS="$CLAUDE_DIR/settings.json"
WITH_HOOKS=0

for a in "$@"; do
  case "$a" in
    --with-hooks) WITH_HOOKS=1 ;;
    -h|--help) sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 64 ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || echo "note: not macOS — play.sh will fall back to paplay/aplay/ffplay if present."

echo "Installing tones and scripts -> $DEST"
mkdir -p "$DEST/mp3"
cp "$SRC"/tones/wav/*.wav "$DEST"/
cp "$SRC"/tones/mp3/*.mp3 "$DEST/mp3"/ 2>/dev/null || true
cp "$SRC"/bin/play.sh "$SRC"/bin/hook.sh "$SRC"/bin/add-hooks.sh "$DEST"/
chmod +x "$DEST/play.sh" "$DEST/hook.sh" "$DEST/add-hooks.sh"

echo "Installing skills            -> $SKILLS"
for s in "$SRC"/skills/*/; do
  name="$(basename "$s")"
  mkdir -p "$SKILLS/$name"
  cp "$s/SKILL.md" "$SKILLS/$name"/
  echo "  $name"
done

# The allowlist pattern must name the path Claude will actually invoke.
if [ "$CLAUDE_DIR" = "$HOME/.claude" ]; then
  PLAY_PATTERN="Bash(~/.claude/audio_notifications/play.sh:*)"
else
  PLAY_PATTERN="Bash($DEST/play.sh:*)"
fi

echo "Allowlisting playback        -> $SETTINGS"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

if command -v jq >/dev/null 2>&1; then
  tmp="$(mktemp)"
  jq --arg play "$PLAY_PATTERN" '
    .permissions //= {} |
    .permissions.allow //= [] |
    .permissions.allow = (
      .permissions.allow
      + ["Bash(afplay:*)", $play]
      | unique
    )
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  jq -r '.permissions.allow[]' "$SETTINGS" | sed 's/^/  /'
else
  echo
  echo "jq not found — add this to $SETTINGS by hand:"
  cat <<JSON
  {
    "permissions": {
      "allow": [
        "Bash(afplay:*)",
        "$PLAY_PATTERN"
      ]
    }
  }
JSON
fi

if [ "$WITH_HOOKS" = 1 ]; then
  echo
  "$DEST/add-hooks.sh"
fi

echo
echo "Test it:   $DEST/play.sh action-complete"
echo "Hooks:     $DEST/add-hooks.sh          (optional, deterministic tones)"
echo "Skills are picked up the next time a Claude Code session starts."
