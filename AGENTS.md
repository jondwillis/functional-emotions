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

Configure via `/plugin config functional-emotions` after install, or
set the corresponding `CLAUDE_PLUGIN_OPTION_<key>` environment variable
before launching Claude. (Legacy `CLAUDE_PLUGIN_CONFIG_<key>` is also
honored for back-compat; new setups should use `OPTION_`.)

### Profile — the one knob most users set

| `profile`  | mode    | guards & anchors & LLM hooks |
|------------|---------|------------------------------|
| `balanced` | loud    | all on                       |
| `quiet`    | gentle  | all on                       |
| `off`      | silent  | all off                      |

`balanced` is the default. `quiet` keeps the model-facing primes but
suppresses ★ banners and the Stop summary. `off` only logs detections.

### Tuning fields (independent of profile)

| Key                        | Type   | Default                       | Notes |
|----------------------------|--------|-------------------------------|-------|
| `failure_spiral_threshold` | number | `3` (range 1–20)              | Consecutive Bash failures before the calm/reflect prime fires. |
| `judge_model`              | string | `claude-haiku-4-5-20251001`   | Used by the LLM-judge hooks (test-edit, Stop verification). |
| `urgency_sensitivity`      | string | `medium` (`low`/`medium`/`high`) | How aggressively to detect pressure language in user prompts. |

### Override fields (blank → derived from profile)

Each of these fields, when blank, takes its value from the profile
bundle above. Setting any of them directly wins over the profile —
useful for narrow exceptions like `profile=off` plus
`enable_review_agent=true`.

| Key                   | Type    | Profile-derived default                     |
|-----------------------|---------|---------------------------------------------|
| `mode`                | string  | balanced→`loud`, quiet→`gentle`, off→`silent` (also accepts deprecated `strict`→`loud`) |
| `guard_test_edits`    | boolean | off→`false`, otherwise `true`               |
| `guard_no_verify`     | boolean | off→`false`, otherwise `true`               |
| `guard_goal_conflict` | boolean | off→`false`, otherwise `true`               |
| `session_baseline`    | boolean | off→`false`, otherwise `true`               |
| `subagent_baseline`   | boolean | off→`false`, otherwise `true`               |
| `post_compact_anchor` | boolean | off→`false`, otherwise `true`               |
| `enable_llm_judge`    | boolean | off→`false`, otherwise `true`               |
| `enable_review_agent` | boolean | off→`false`, otherwise `true`               |

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
