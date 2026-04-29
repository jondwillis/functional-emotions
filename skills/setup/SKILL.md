---
name: setup
description: One-time setup for functional-emotions in the current project — idempotently adds `.claude/.functional-emotions/` to the project's `.gitignore` so the plugin's per-session state files (TSV logs, markdown writeups, eval DB) don't get committed. Safe to re-run. Use after installing the plugin in a new project, or when the user mentions accidentally committing functional-emotions state, or when troubleshooting "why are my session files showing in git status?".
disable-model-invocation: false
allowed-tools: Bash
---

Run a one-time, idempotent setup pass that gitignores the plugin's
state directory. The plugin writes a TSV event log, markdown session
writeups, and (optionally) a DuckDB file under
`${CLAUDE_PROJECT_DIR}/.claude/.functional-emotions/`. Without a
gitignore entry, those files appear in `git status` and risk being
committed.

**This skill only writes to `.gitignore`. It never touches existing
state files, never deletes anything, and never modifies git config.**

Steps:

1. **Confirm we're in a git repo.** Run `git -C "${CLAUDE_PROJECT_DIR}"
   rev-parse --is-inside-work-tree` (or `pwd` if `CLAUDE_PROJECT_DIR`
   is unset). If not a git repo, tell the user "Not in a git repo — no
   setup needed (state files go to `${TMPDIR}` instead)" and stop.

2. **Check if the path is already ignored.** Use git's own resolver,
   which respects `.gitignore`, `.git/info/exclude`, parent
   `.gitignore`s, and the global gitignore. Create a sentinel file
   path that doesn't need to exist:

   ```bash
   git -C "${CLAUDE_PROJECT_DIR}" check-ignore -q .claude/.functional-emotions/sentinel
   ```

   Exit code 0 = already ignored. Exit code 1 = not ignored. Exit
   code 128 = error. If already ignored, tell the user "Already
   gitignored — no changes needed" and stop.

3. **Append to `.gitignore`.** Append the pattern with a one-line
   header comment so it's discoverable later:

   ```bash
   {
     printf '\n# functional-emotions plugin state (per-session logs, writeups, eval DB)\n'
     printf '.claude/.functional-emotions/\n'
   } >> "${CLAUDE_PROJECT_DIR}/.gitignore"
   ```

   If `.gitignore` doesn't exist yet, this creates it.

4. **Verify.** Re-run the `git check-ignore` from step 2 and confirm
   exit code 0. If verification fails, tell the user the append
   succeeded but git's resolver still doesn't see it (rare — usually
   means a competing `!` negation pattern earlier in the file), and
   show them the appended lines so they can sort it out.

5. **Report.** Tell the user: "Added `.claude/.functional-emotions/`
   to `.gitignore`. Re-run this skill anytime — it's idempotent." If
   relevant, mention what's inside the state dir:
   - **Canonical** (must persist): `session-*.tsv`, `labels.jsonl`
   - **Derived** (regenerable): `sessions/*.md`, `eval.duckdb` + `.wal`
   - **Legacy** (safe to delete): `cbt.duckdb*`

Do not stage or commit the `.gitignore` change. The user decides when
that gets committed.
