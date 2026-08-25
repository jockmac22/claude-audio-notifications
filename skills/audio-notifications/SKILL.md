---
name: audio-notifications
description: Play a short notification tone on the user's Mac to signal a state change out loud — action complete, input required, still working, action failed, or system failed. Use when the user asks to be notified by sound, has asked for tones on long-running work, or when finishing a task they stepped away from. Only works on the local machine, not in sandboxed or remote environments.
---

# Audio notifications

Five short tones (0.33–0.47s) that let a long-running task speak without words.
Positive states are major and rising; negative states are minor and falling. The
final gesture of each carries the punctuation.

## Playing a tone

Run the helper script with the tone name:

```bash
~/.claude/audio_notifications/play.sh action-complete
```

It resolves the tone directory itself, so it works from any working directory.
If the script is missing, play the file directly:

```bash
afplay ~/.claude/audio_notifications/positive_action-complete.wav
```

Set `CLAUDE_TONES` to point at a tone directory somewhere else.

## The tones

| Name | Meaning | Reads as | Use when |
|---|---|---|---|
| `action-complete` | Everything is done | `!` | The whole task is finished and nothing is pending. Once, at the end — not per step. |
| `input-required` | Blocked on the user | `?` | You are stopping to ask a question or need a decision before continuing. |
| `in-process` | Still working | `.` | A long operation is mid-flight and the user may wonder if it stalled. Rate-limited to once per 30s by the script; never call it in a loop — for a deliberate repeating heartbeat use the **notify-while-thinking** skill. |
| `action-failed` | The task failed | `!` | You attempted the work and could not complete it. |
| `system-failed` | The environment failed | `?` | Something outside the task broke — missing tool, no network, bad credentials. Distinct from the task itself failing. |

## Rules

- **One tone per moment.** Never chain two tones together; they are sentences, not syllables.
- **Do not play a tone for every tool call.** `action-complete` marks the end of the
  whole request, not the end of each step.
- **Ask before making noise the first time in a session** unless the user has already
  asked for tones, set up hooks, or is clearly away from the keyboard.
- **Silence is not failure.** If `afplay` is unavailable or the environment is
  sandboxed, skip the tone and carry on — never report it as an error, and never
  retry with a different audio tool.
- **Non-macOS:** `play.sh` tries `afplay`, then `paplay`, `aplay`, `ffplay`. If
  none exist it exits 0 without a sound — treat that as silence, not an error.

## Regenerating

`tones/make_tones.py` in the claude-audio-notifications repo rebuilds every tone
from scratch (it is not installed into `~/.claude`). Two
constants control the character: `TRANSPOSE` (pitch shift in octaves, fractions
allowed) and `TIME` (scales note starts, lengths, decays and reverb together).
It writes the WAVs to `tones/wav/`. Requires numpy; the MP3s in `tones/mp3/`
are encoded with ffmpeg.
