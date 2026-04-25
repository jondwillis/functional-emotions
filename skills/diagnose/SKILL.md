---
name: diagnose
description: Show the cbt-hooks plugin's session state — which interventions fired, when, and why. Use when you want to know what the plugin has done this session, or want to debug whether a hook fired as expected.
disable-model-invocation: false
allowed-tools: Bash
---

Show the user a summary of what this plugin has detected and intervened on
during the current session.

1. Locate the state file:
   - `${CLAUDE_PROJECT_DIR}/.claude/.cbt-hooks/session-<id>.tsv` for
     project sessions, or
   - `${TMPDIR}/cbt-hooks-${USER}/session-<id>.tsv` otherwise.
2. If the file is missing, say "No interventions yet this session." and stop.
3. Otherwise render it as a small table. Columns: `time`, `kind`, `detail`.
   Truncate `detail` to 80 chars.
4. End with a one-line interpretation: e.g. *"3 failure-spiral primes fired
   during the test runs at 14:02–14:11."*

Do not invent rows. If the file is empty, say so.
