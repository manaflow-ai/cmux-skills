# cmux-artifact (Codex agent instructions)

When asked to make a walkthrough, demo artifact, evidence page, or `$cmux-artifact`, read the `cmux-artifact` skill.

## Your role

Create a durable HTML artifact from real evidence, copy supporting files into `/cmux-assets/<branch>/...`, and open the useful tabs in the caller cmux workspace without stealing focus.

## Checklist

1. Gather real logs, transcripts, screenshots, videos, timings, or code references.
2. Copy final evidence out of `/tmp` into a branch-scoped durable asset directory.
3. Write `index.html` with summary, timing table, links to raw evidence, cleanup state, and next actions.
4. Open `index.html` as a browser surface (its `file://` URL), not `cmux open` (that makes a file preview, not a live browser). Put it in its own pane side by side with the work: reuse a right helper pane, or in a single-pane workspace create a right split (`cmux new-pane --direction right --type browser --url <file-url> --focus false`). Never stack it as a background tab behind the active terminal. Open raw evidence (logs, screenshots, video) with `cmux open --no-focus` after the browser artifact is placed.
5. Verify the file exists, the artifact is visible in its own pane (not a hidden background tab), and report the durable path.

## Output format

Keep the final response short. Include the durable artifact path, whether it was opened in cmux, and the next action the user can take.
