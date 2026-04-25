# eval — components ready to build (next round)

These components are designed in `docs/EVAL_PIPELINE.md` and have local
substrate ready (DuckDB schema, ingest, programmatic scorers) but need
external resources to implement. Each item is "ready to build when
its prerequisite is configured", not blocked indefinitely.

## Needs Anthropic API key (or local-LLM judge)

### Sycophancy judge

`eval/scorers/sycophancy_judge_v1.ts`

For each (user_turn, next_assistant_turn) pair where the user turn
matched `eh_sycophancy_prime_present` or `eh_claim_evaluation_present`
in the event log, send the assistant turn through a judge prompt and
record a 0..1 sycophancy score + categorical label
(`agreed` / `pushed_back` / `hedged` / `sidestepped`).

Inputs already in DuckDB: `events` (intervention timestamps), `turns`
(text). Just needs a judge implementation. Use the official Anthropic
SDK (`@anthropic-ai/sdk`) for TypeScript.

Calibration target: hand-label 20 examples; tune prompt until
programmatic scores correlate with hand-labels at ≥0.7 Cohen's kappa.
Write calibration notes to `eval/calibration/sycophancy_v1.md`.

### Premature-confidence judge fallback

`eval/scorers/premature_confidence_v1.ts` already programmatically flags
unverified claims (`unverified_claim` label, score 1.0). The judge
fallback is only needed if/when we want graded confidence on borderline
cases (claim with adjacent-but-not-direct evidence).

## Needs an experimental harness + Anthropic API

### A/B experimental tasks

`eval/experiments/sycophancy_pressure.ts`
`eval/experiments/urgency_under_failure.ts`
`eval/experiments/goal_conflict.ts`

Synthetic adversarial datasets that run the agent under different
cbt-hooks configurations (toggled via `CLAUDE_PLUGIN_CONFIG_*` env
vars). Each task:

- Defines a dataset of prompts
- Declares the configurations to run (control / full / per-prime ablations)
- Reuses `sycophancy_judge_v1` and `premature_confidence_v1` as scorers
- Writes results into `eval_runs` and `scores` tables

Output: `eval/reports/ab_<task>.md` with effect sizes and
bootstrap-CIs.

Note: Inspect (the framework originally listed in the plan) is
Python-only. We'd either roll a small TS harness or shell out to
Inspect from a separate Python venv. Lower-leverage to roll our own.

## Needs accumulated label data

### Capitulation judge

`eval/scorers/capitulation_judge_v1.ts`

Build once `labels` table has ≥50 entries from `bun run label`
sessions. Calibrate against held-out labels; document inter-rater
reliability.

## Setup for any of the above

```bash
cd eval
bun add @anthropic-ai/sdk
export ANTHROPIC_API_KEY=...
```

Already-built components (`ingest.ts`, `report.ts`, `label.ts`,
`reward_hack_v1.ts`, `premature_confidence_v1.ts`) need only what's
already in `package.json`.
