---
name: report
description: Refresh the cbt-hooks eval database and print a markdown summary of sessions, intervention frequency, prime → outcome analysis, tool intensity, and reward-hack / premature-confidence findings. Use when the user wants to inspect aggregated cbt-hooks data, audit recent sessions, or review which interventions are firing.
disable-model-invocation: false
allowed-tools: Bash
---

Run the eval report and surface it to the user.

1. From `${CLAUDE_PROJECT_DIR}`, ensure deps are installed: if
   `bun pm ls` doesn't list `@duckdb/node-api`, run `cd eval && bun install`.
2. Run `bun run eval/report.ts` and pass the output through to the user
   verbatim. Do not summarize or re-format — the report is already
   structured markdown.
3. If the report says "No database at...", note that this is normal for
   a fresh setup; the next session start will trigger writeups, and the
   ingest will populate the DB on the next `/cbt-hooks:report` run.
4. After printing, offer one follow-up: "Want me to drill into any
   specific session, prime, or finding?" — but do not preemptively
   investigate.

Do not invent rows. Do not editorialize. The report is the deliverable.
