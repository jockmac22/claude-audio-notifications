#!/usr/bin/env bash
# Add (or refresh) the notification-tone hooks in ~/.claude/settings.json.
#
#   ./add-hooks.sh          install / refresh the hooks
#   ./add-hooks.sh --idle   also chime when Claude has been left waiting
#   ./add-hooks.sh --remove take the tone hooks back out
#
# Idempotent: existing audio_notifications hook entries are stripped and
# rewritten, so re-running never stacks duplicates. Backs up settings first.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK="$CLAUDE_DIR/audio_notifications/hook.sh"
WANT_IDLE=0
REMOVE=0
for a in "$@"; do
  case "$a" in
    --idle) WANT_IDLE=1 ;;
    --remove) REMOVE=1 ;;
    *) echo "unknown option: $a" >&2; exit 64 ;;
  esac
done

command -v jq >/dev/null || { echo "jq is required" >&2; exit 69; }
[ -x "$HOOK" ] || { echo "not found or not executable: $HOOK (run install.sh first)" >&2; exit 66; }

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

tmp="$(mktemp)"

# strip any hook group that references our script, then drop emptied events
strip='
  def clean:
    with_entries(
      .value |= ( map( .hooks |= map(select((.command // "") | contains("audio_notifications") | not))
                     | select((.hooks | length) > 0) ) )
    ) | with_entries(select((.value | length) > 0));
  if has("hooks") then .hooks |= clean else . end
'

if [ "$REMOVE" = 1 ]; then
  jq "$strip" "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "Tone hooks removed from $SETTINGS"
  exit 0
fi

jq --arg hook "$HOOK" --argjson idle "$WANT_IDLE" "
  $strip
  | .hooks //= {}

  # Claude is blocked on you -> question tone
  | .hooks.Notification = ((.hooks.Notification // []) + [
      { matcher: \"permission_prompt\",
        hooks: [{ type: \"command\", command: (\$hook + \" input-required\"), timeout: 5 }] },
      { matcher: \"elicitation_dialog\",
        hooks: [{ type: \"command\", command: (\$hook + \" input-required\"), timeout: 5 }] }
    ] + (if \$idle == 1 then [
      { matcher: \"idle_prompt\",
        hooks: [{ type: \"command\", command: (\$hook + \" input-required\"), timeout: 5 }] }
    ] else [] end))

  # turn finished -> done tone
  | .hooks.Stop = ((.hooks.Stop // []) + [
      { hooks: [{ type: \"command\", command: (\$hook + \" action-complete\"), timeout: 5 }] }
    ])

  # turn ended on an API error -> system tone
  | .hooks.StopFailure = ((.hooks.StopFailure // []) + [
      { hooks: [{ type: \"command\", command: (\$hook + \" system-failed\"), timeout: 5 }] }
    ])
" "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "Hooks written to $SETTINGS:"
jq '.hooks | with_entries(.value |= map(.hooks[].command))' "$SETTINGS"
echo
echo "Settings reload automatically; /hooks shows what is registered."
