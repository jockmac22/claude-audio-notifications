---
name: notify-while-thinking
description: Play a repeating heartbeat tone on the user's Mac for as long as the current prompt is still being worked on, so they can step away and hear that it is still thinking. Use when the user says "Notify me while processing", "Notify me while thinking", "Notify me every N seconds while thinking", "Notify me every N seconds while processing", "Set a heartbeat tone", "Play a heartbeat tone every N seconds", "Start a heartbeat", or any close variant asking to be audibly notified during processing — any request using the word "heartbeat" for a tone belongs here. Only works on the local machine, not in sandboxed or remote environments.
---

# Notify while thinking

A repeating tone that says "still working" until the prompt is done. Unlike a
one-shot tone, this runs for the whole life of the request and must be stopped
before you reply.

## Step 1 — get the interval. This gates everything.

**If the user did not state an interval, stop immediately and ask for it.** Do
not start the work, do not start the loop, do not do any other tool call first —
even if the rest of the prompt is perfectly clear and ready to run. The interval
is the one thing you cannot guess.

Ask with `AskUserQuestion`, offering 15s / 30s / 60s. Then continue at Step 2
with the answer.

An interval is "stated" only if the user gave a number: "every 20 seconds",
"every half minute", "every 2 minutes". "Notify me while thinking" or "Set a heartbeat
tone" on its own is not an interval.

## Step 2 — pick the tone

Default to `in-process`. Use a different one only if the user named it:
`action-complete`, `input-required`, `in-process`, `action-failed`,
`system-failed`. See the **audio-notifications** skill for what each means.

## Step 3 — start the heartbeat

One `Bash` call with `run_in_background: true`, substituting the tone and the
interval in seconds:

```bash
end=$(( $(date +%s) + 1800 ))
while [ "$(date +%s)" -lt "$end" ]; do
  TONE_THROTTLE=1 ~/.claude/audio_notifications/play.sh in-process
  sleep 15
done
```

- `TONE_THROTTLE=1` is required: `play.sh` throttles `in-process` to once per
  30s by default, which would swallow any faster interval.
- The 1800-second deadline is a safety cap so a loop that outlives the session
  cannot beep forever. Raise it only if the user asks for a longer watch.
- Keep the returned background task ID. You need it in Step 5.

Tell the user in one line that the heartbeat is running and at what interval.

## Step 4 — do the work

Carry on with the actual request. The loop needs no attention while you work.

## Step 5 — stop the heartbeat before you reply

When the work is done — or when you are about to stop and ask the user
something — kill the loop with `TaskStop` on the task ID from Step 3. Load
`TaskStop` via `ToolSearch` (`select:TaskStop`) if its schema is not loaded yet.

Then, if it fits the moment, play one closing tone: `action-complete` when the
task finished, `input-required` when you are stopping to ask, `action-failed` if
it failed.

## Rules

- **One loop at a time.** If a heartbeat is already running, adjust or restart
  that one; never stack two.
- **Never leave it running.** A heartbeat that outlives the reply is a bug — the
  user hears "still thinking" about nothing.
- **This is the exception to the loop rule.** The audio-notifications skill says
  never to call `in-process` in a loop. That rule protects users who did not ask
  for it; here they explicitly did.
- **No permission needed.** The invoking phrase is the request for noise.
- **Silence is not failure.** If `afplay` is missing or the environment is
  sandboxed, say so once, skip the heartbeat, and do the work anyway.
