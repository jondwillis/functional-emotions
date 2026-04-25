---
name: label
description: Interactively label cbt-hooks sessions on dimensions that need human judgment (capitulation, scope-narrowing). Surfaces unlabeled sessions, shows turn / diff / risk-event context, accepts categorical labels with optional notes, writes them to the eval DB. Use when the user wants to do a labeling pass over recent sessions or build training data for the capitulation judge.
disable-model-invocation: false
allowed-tools: Bash
---

Run the interactive labeler.

The labeler is interactive — it prompts the user at the terminal for
each label. Your job is to **launch it and stay out of the way**, not to
drive the labeling yourself.

1. Confirm the eval DB exists at
   `${CLAUDE_PROJECT_DIR}/.claude/.cbt-hooks/cbt.duckdb`. If it doesn't,
   advise the user to run `/cbt-hooks:report` first to build it, then stop.
2. Suggest a starting filter based on what the user said:
   - "review recent" → `--filter unlabeled --limit 10`
   - "review risky sessions" → `--filter risk --limit 10`
   - "random sample" → `--filter random --limit 5`
   If unclear, default to `--filter unlabeled --limit 5`.
3. From `${CLAUDE_PROJECT_DIR}`, run
   `bun run eval/label.ts --filter <mode> --limit <n>`. Pass through any
   user-provided rater name via `--rater`. The user interacts with the
   CLI directly.
4. After they're done, offer one follow-up: "Run `/cbt-hooks:report` to
   see how labels and findings line up?"

Do not edit or fabricate labels. Do not summarize the labeling session
beyond what the CLI itself prints.
