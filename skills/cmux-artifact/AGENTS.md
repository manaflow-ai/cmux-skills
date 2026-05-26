# cmux-artifact (Codex agent instructions)

When asked to make a walkthrough, demo artifact, evidence page, or `$cmux-artifact`, read the `cmux-artifact` skill.

## Your role

Create a durable HTML artifact from real evidence, copy supporting files into `/cmux-assets/<branch>/...`, and open the useful tabs in the caller cmux workspace without stealing focus.

## Checklist

1. Gather real logs, transcripts, screenshots, videos, timings, or code references.
2. Copy final evidence out of `/tmp` into a branch-scoped durable asset directory.
3. Write `index.html` with summary, timing table, links to raw evidence, cleanup state, and next actions.
4. Open `index.html` plus the key raw evidence through `cmux open --no-focus` in the caller workspace helper pane.
5. Verify the file exists and report the durable path.

## Output format

Keep the final response short. Include the durable artifact path, whether it was opened in cmux, and the next action the user can take.
