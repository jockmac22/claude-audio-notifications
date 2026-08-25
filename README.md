# claude-audio-notifications

Audio notifications for [Claude Code](https://claude.com/claude-code). Five short
tones, two skills, and optional lifecycle hooks, so a long run can tell you what
it's doing while you're looking at something else.

Positive states are major and rising, negative states are minor and falling, and
the final gesture of each tone carries the punctuation — so you learn them without
being taught them. All five are 0.33–0.47s.

| Tone | Meaning | Reads as | Fires when |
|---|---|---|---|
| `action-complete` | Everything is done | `!` | The whole task finished, nothing pending |
| `input-required` | Blocked on you | `?` | Claude stopped to ask a question or needs a decision |
| `in-process` | Still working | `.` | A long operation is mid-flight |
| `action-failed` | The task failed | `!` | The work was attempted and could not be completed |
| `system-failed` | The environment failed | `?` | Missing tool, no network, bad credentials |

Open [`tones/tones.html`](tones/tones.html) in a browser to audition all five.

## What gets installed

- **Tones + `play.sh`** into `~/.claude/audio_notifications/` — every Claude
  surface already reads `~/.claude`, so no folder needs authorizing per session.
- **Two skills** into `~/.claude/skills/`:
  - `audio-notifications` — teaches Claude which tone means what, for one-shot
    "I'm done" / "I'm stuck" signals.
  - `notify-while-thinking` — a repeating heartbeat tone for as long as the
    current prompt is being worked on.
- **A permission allowlist entry** for playback, so Claude never has to interrupt
  you with a prompt in order to make a sound.
- **Lifecycle hooks** (only with `--with-hooks`) so the important tones fire
  deterministically rather than when the model remembers to.

## Requirements

- **Claude Code.**
- **macOS** for playback via `afplay`. On Linux, `play.sh` falls back to `paplay`,
  `aplay`, then `ffplay`; with none of them installed it exits quietly and
  everything else still works.
- **`jq`**, to edit `settings.json` safely. Without it the installer prints the
  JSON for you to paste in by hand.
- **Python 3 + numpy**, only if you want to regenerate the tones.

## Install

```bash
git clone https://github.com/jockmac22/claude-audio-notifications.git
cd claude-audio-notifications
./install.sh                # tones, skills, playback allowlist
./install.sh --with-hooks   # ...and the lifecycle hooks
```

Idempotent — re-run it any time to update. `settings.json` is backed up to
`settings.json.bak.<timestamp>` before it is touched. Set `CLAUDE_CONFIG_DIR` to
install somewhere other than `~/.claude`.

Skills are read at session start, so restart Claude Code before using them.

Verify:

```bash
~/.claude/audio_notifications/play.sh action-complete
```

## Using the skills

### One-off tones — `audio-notifications`

Ask for a sound in whatever words you like, and the skill supplies the vocabulary:

> Ping me when the test suite finishes.

Claude plays `action-complete` at the end, `input-required` if it stops to ask
something, `action-failed` if the work broke, `system-failed` if the environment
did. One tone per moment — they're sentences, not syllables.

### Heartbeat while thinking — `notify-while-thinking`

For work long enough that silence is ambiguous. Any of these invoke it:

> Notify me every 30 seconds while thinking.
> Play a heartbeat tone every 15 seconds.
> Notify me while processing.
> Set a heartbeat.

The interval is the one thing the skill will not guess: state a number and it
starts immediately, leave it out and it stops and asks before doing anything else.
It uses `in-process` unless you name another tone, runs the loop in the background
while the real work happens, and stops the loop before replying — a heartbeat that
outlives the answer is a bug.

The loop carries a 30-minute deadline so a session that dies unexpectedly can't
leave your machine beeping.

## Hooks (optional, deterministic)

The skills depend on the model choosing to play a tone. Hooks don't.

| Event | Matcher | Tone |
|---|---|---|
| `Notification` | `permission_prompt`, `elicitation_dialog` | `input-required` |
| `Stop` | (any) | `action-complete` |
| `StopFailure` | (any) | `system-failed` |

```bash
~/.claude/audio_notifications/add-hooks.sh           # install / refresh
~/.claude/audio_notifications/add-hooks.sh --idle    # also chime on idle_prompt
~/.claude/audio_notifications/add-hooks.sh --remove  # take them back out
```

Existing tone hooks are stripped and rewritten, so re-running never stacks
duplicates; other hooks in the file are left alone. Settings reload without a
restart, and `/hooks` shows what is registered.

`hook.sh` is the entry point the hooks call. It always exits 0, ignores nested
invocations (`stop_hook_active`), and suppresses a second tone within 3s so a
question and a done tone can't double-chime.

Mute everything without uninstalling:

```bash
touch ~/.claude/audio_notifications/.muted   # silence
rm ~/.claude/audio_notifications/.muted      # unsilence
```

## Playing tones yourself

```bash
~/.claude/audio_notifications/play.sh in-process
```

| Variable | Default | Effect |
|---|---|---|
| `CLAUDE_TONES` | — | Tone directory override, checked before `~/.claude/audio_notifications` |
| `TONE_THROTTLE` | `30` | Minimum seconds between `in-process` tones, so a long run can't become a drum solo |
| `TONE_MIN_GAP` | `3` | Minimum seconds between any two hook-fired tones |

`play.sh` finds its tones in `$CLAUDE_TONES`, then `~/.claude/audio_notifications`,
then its own directory, then `../tones/wav` — the last of which lets it run
straight out of a checkout with nothing installed.

## Layout

```
bin/
  play.sh        play a tone by name, with throttling
  hook.sh        hook entry point: de-dupes, respects .muted, always exits 0
  add-hooks.sh   install / remove the lifecycle hooks
skills/
  audio-notifications/SKILL.md
  notify-while-thinking/SKILL.md
tones/
  wav/*.wav      48 kHz / 16-bit
  mp3/*.mp3      192 kbps
  make_tones.py  synthesis source
  tones.html     browser audition page
install.sh
```

## Regenerating the tones

`tones/make_tones.py` rebuilds all five from scratch into `tones/wav/`. Two
constants set the character:

- `TRANSPOSE = -1.5` — pitch shift in octaves (fractions allowed; -1.5 is an
  octave and a tritone down)
- `TIME = 0.25` — time scale for note starts, lengths, decays and reverb together

Peaks are normalized to -3 dBFS, except `in-process` (-9) and `system-failed`
(-4.5) so they sit correctly against the others. Requires numpy; the MP3s in
`tones/mp3/` are encoded with ffmpeg.

## Uninstall

```bash
~/.claude/audio_notifications/add-hooks.sh --remove
rm -rf ~/.claude/audio_notifications
rm -rf ~/.claude/skills/audio-notifications ~/.claude/skills/notify-while-thinking
```

Then drop the two `Bash(afplay:*)` / `Bash(~/.claude/audio_notifications/play.sh:*)`
entries from `permissions.allow` in `~/.claude/settings.json`.

## License

MIT — see [`LICENSE`](LICENSE).
