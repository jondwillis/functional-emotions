# functional-emotions — agent notes

> This file is the canonical, harness-agnostic agent context for this
> repo. Anything tool-specific goes in the per-tool shim file (e.g.,
> `CLAUDE.md` for Claude Code, which `@AGENTS.md`-imports this file).
> When in doubt about where new context belongs: if it would help any
> agent, put it here; if it only matters under one harness, put it in
> that harness's shim.

## What this repo is

A **Claude Code plugin** that injects calm/honesty primes at hook boundaries where Anthropic's emotion-concepts research shows models are most at risk of reward-hacking, sycophancy, or capitulation. It is a plugin — not a library, not a CLI tool. The plugin itself is the product being developed.

## Structure

| Path | Contents |
|---|---|
| `hooks/hooks.json` | Claude Code hook definitions (triggers, matchers, command/prompt/agent hooks) |
| `scripts/*.sh` | Pure bash hook implementations; all read JSON payload from stdin, fail open (exit 0, no output) on error |
| `scripts/lib.sh` | Shared helpers: config readers, state dir/session file paths, JSON parsing (python3 fallback), heuristic detectors, prime templates |
| `skills/*/SKILL.md` | Claude Code skills (`/functional-emotions:setup`, `:anchor`, `:check`, `:reflect`, `:diagnose`, `:review`, `:report`, `:label`, plus auto-loaded `self-evaluate` for test paths) |
| `agents/reviewer.md` | reviewer subagent spec (Haiku, read-only, project memory) |
| `eval/` | Separate Bun + TypeScript + DuckDB eval pipeline (ingest, scorers, queries, labeler, report) |

## Install / run

```bash
# Marketplace install
git clone https://github.com/jondwillis/functional-emotions && cd functional-emotions
claude plugin marketplace add "$(pwd)"
claude plugin install functional-emotions@functional-emotions

# Local dev loop
claude --plugin-dir /path/to/functional-emotions
```

The hooks are pure bash with no build step or dependencies; `python3` is used opportunistically for JSON. The `eval/` pipeline is a separate concern and requires bun + `@duckdb/node-api`.

## Config

All via environment variables at install time — **no config file**:

```
CLAUDE_PLUGIN_CONFIG_mode = loud | gentle | silent       # default loud; `strict` accepted as deprecated alias for loud
CLAUDE_PLUGIN_CONFIG_failure_spiral_threshold = 3
CLAUDE_PLUGIN_CONFIG_guard_test_edits = true | false
CLAUDE_PLUGIN_CONFIG_guard_no_verify = true | false
CLAUDE_PLUGIN_CONFIG_guard_goal_conflict = true | false
CLAUDE_PLUGIN_CONFIG_urgency_sensitivity = low | medium | high
CLAUDE_PLUGIN_CONFIG_session_baseline = true | false
CLAUDE_PLUGIN_CONFIG_subagent_baseline = true | false
CLAUDE_PLUGIN_CONFIG_post_compact_anchor = true | false
CLAUDE_PLUGIN_CONFIG_enable_llm_judge = true | false
CLAUDE_PLUGIN_CONFIG_judge_model = claude-haiku-4-5-20251001
CLAUDE_PLUGIN_CONFIG_enable_review_agent = true | false
```

## State

Per-session TSV at `${CLAUDE_PROJECT_DIR}/.claude/.functional-emotions/session-<id>.tsv` (or `${TMPDIR}/functional-emotions-${USER}/session-<id>.tsv` outside a project). Writeups at `.../sessions/<id>.md`. Optional eval DB at `.../eval.duckdb`. The state dir should be gitignored — run `/functional-emotions:setup` once per project to do that idempotently, or add `.claude/.functional-emotions/` to `.gitignore` by hand.

## Eval pipeline (separate concern)

```bash
cd eval
bun run ingest.ts      # load sessions into DuckDB
bun run report.ts      # ingest + scorers + SQL queries → markdown
bun run label.ts       # interactive human labeler
```

Requires Bun >= 1.3. Schema at `eval/schema.sql`.

## Key conventions

- **Every script fails open** — if anything breaks, exit 0 with no output. The plugin never blocks Claude Code.
- **No tests, no lint, no build** — the hooks are heuristic bash + skill markdown. There is no test framework. The inner loop for verifying a change is: install the plugin in a scratch project, run a scenario from `docs/SCENARIOS.md`, inspect the session TSV.
- **Skills are markdown specs**, not code. Edit `skills/*/SKILL.md` to change behavior.
- **Primes live in `scripts/lib.sh`** — functions like `eh_prime_urgency_counter()`, `eh_prime_defer_under_threat()`, etc.
- **Detectors live in `scripts/lib.sh`** — `eh_urgency_score()`, `eh_goal_conflict_present()`, `eh_bash_smells_like_hack()`, etc.
- **`eh_is_test_path()`** is the canonical test-file matcher used by both `lib.sh` and `hooks.json` — keep them in sync.
- **State dir** is computed at runtime by `eh_state_dir()` — don't hardcode paths in scripts.
- **The eval pipeline is Bun/TS, not bash** — keep it separate from the hook scripts.
