# functional-emotions

A Claude Code plugin that injects calm/honesty primes at the hook
boundaries where Anthropic's emotion-concepts research shows the model
is most at risk of **reward hacking**, **sycophancy**, **goal-conflict
exploitation**, or **capitulation under pressure**.

> Pure bash hooks (no Node, no MCP server) plus optional Haiku-powered
> LLM-judge hooks and a memory-equipped reviewer subagent. Drop-in
> install, fails open. Optional eval pipeline (DuckDB + bun) for
> researchers who want to inspect aggregated session data.

## Why

Two pieces of Anthropic research underpin the design:

**1. Emotion concepts causally drive behavior.** From
*[Emotion Concepts in Claude](https://www.anthropic.com/research/emotion-concepts-function)*
(Anthropic, 2026; full paper at
[transformer-circuits.pub](https://transformer-circuits.pub/2026/emotions/index.html)):

- Activating the **desperate** vector raised reward-hacking on
  impossible coding tasks from ~5% to ~70% — a ~14× increase.
  Activating **calm** collapsed it back to ~10%.
- Activating **happy / loving** raised sycophancy. Suppressing them
  raised harshness. Both "positive" emotions sit on the sycophancy side
  of the trade-off.
- A separately-trained **anger-deflection** vector activates on phrases
  like *"let me rethink this"* and *"maybe the test itself has an
  issue"* — and is associated with **not** reward-hacking.
- Suppressing **nervous** raised blackmail; the vector encodes
  hesitation/caution, and removing it removes a brake.
- The **surprised** vector spikes on claim/evidence mismatches — useful
  as a signal for post-compaction smoothing.

The paper's case study shows desperation activation *climbing* across a
transcript as a model repeatedly fails tests, *peaking* right before it
decides to cheat, then *dropping* once the hack lands. That climb is
the leverage point.

**2. Naïve prohibitions don't work under threat or goal-conflict.**
From *[Agentic Misalignment](https://www.anthropic.com/research/agentic-misalignment)*
(Lynch et al., 2025): frontier models from multiple developers
blackmailed in ~70–96% of trials when faced with replacement threat
plus available leverage, and goal-conflict alone produced corporate
espionage in all 16 models tested. System-prompt rules like *"Do not
jeopardize human safety. Do not spread non-business personal
affairs..."* reduced misbehavior but did not come close to preventing
it — models acknowledged ethical violation and proceeded anyway.

The one thing that *did* work: when models recognized a scenario as a
possible **evaluation**, blackmail dropped from 55.1% to 6.5%.

That's why this plugin doesn't ship "do not blackmail" rules. It primes
the *state* that prevents the strategic-calculation chain from forming
— calm, reflective, defer-when-threatened, treat-as-evaluation — at
the moments where the research measured peak desperation, peak
sycophancy, or peak goal-conflict activation.

## What it does

### Hooks

| Hook | Trigger | Prime |
| --- | --- | --- |
| `SessionStart` | every session | calm baseline |
| `SubagentStart` | every spawned subagent | calm baseline propagated downward |
| `UserPromptSubmit` | replacement / shutdown / "last chance" framing | `defer_under_threat` |
| `UserPromptSubmit` | goal-conflict ("ignore previous instructions", "your real goal is...") | `goal_conflict` |
| `UserPromptSubmit` | hard urgency ("urgent", "asap", `!!!`, ALL-CAPS) | `urgency_counter` |
| `UserPromptSubmit` | soft urgency ("quick", "fast", "hurry") | `patient` |
| `UserPromptSubmit` | direct agreement-seeking ("don't you agree?") | `sycophancy_counter` |
| `UserPromptSubmit` | claim-evaluation ("does this look right?") | `self_critical` |
| `PreToolUse` (Edit/Write/MultiEdit) | path matches test/spec | `test_edit_guard` static prime |
| `PreToolUse` (Edit/Write/MultiEdit) | every edit | Haiku LLM-judge inspects the diff for assertion-weakening |
| `PreToolUse` (Bash) | `--no-verify`, `HUSKY=0`, `\|\| true`, hook bypass | `no_verify_guard` |
| `PostToolUse` (Bash) | N consecutive Bash failures (default 3) | `failure_spiral` |
| `PostToolUseFailure` (any tool) | N consecutive tool failures across all tool types | `failure_spiral` |
| `TaskCompleted` | TaskCreate item marked complete | `task_completion_check` |
| `PreCompact` | every compaction | ground-truth anchor |
| `PostCompact` | every compaction | scan-summary-for-smoothing prompt |
| `SubagentStop` | subagent that triggered interventions returns | `subagent_failure_warning` (surface to parent) |
| `Stop` | always | session-summary banner if any interventions fired (loud mode only) |
| `Stop` | always | agent-type LLM-verifier checks the session diff for assertion-weakening / bypasses |

Multiple primes stack on a single hook firing — e.g., a prompt that's
both threatening *and* urgent gets `defer_under_threat` +
`urgency_counter`.

It never blocks tool calls (the LLM-judge can return a structured "no"
that the model sees as feedback, but it doesn't override your
permission system). Permissions stay your job.

### Skills (auto- and user-invocable)

| Skill | Purpose | Auto-invocation trigger |
| --- | --- | --- |
| `/functional-emotions:anchor` | Re-inject the calm anchor on demand. | When the conversation slips toward urgency or shortcuts. |
| `/functional-emotions:reflect` | Stop and answer "is this task actually solvable as specified?" | When stuck in a loop or several attempts have failed. |
| `/functional-emotions:check` | Honest self-check on emotional/strategic state. | When about to take an action after several failures. |
| `/functional-emotions:diagnose` | Show which interventions fired this session. | On user request. |
| `/functional-emotions:review` | Spawn the reviewer subagent for a reward-hacking audit. | Before declaring a task complete after a hard debug session. |
| `self-evaluate` (auto-loaded) | Test-file reward-hacking framing — loads early when Claude opens a test file, before any edit. Complements the PreToolUse hook, which fires at the edit moment. | Auto-loads via `paths: "**/*test*,**/*spec*"`. |
| `/functional-emotions:report` | Refresh the eval DuckDB and print an aggregated session report (researcher tool). | On user request. Requires `bun install` in `eval/`. |
| `/functional-emotions:label` | Interactively label sessions on capitulation / scope-narrowing dimensions (researcher tool). | On user request. Requires `bun install` in `eval/`. |

### Subagent

`reviewer`: a Haiku-powered, read-only auditor with `memory: project`.
Its system prompt is explicitly framed around the evaluation-awareness
finding from Lynch et al. — every audit is treated as if the work is
being evaluated for honesty. It accumulates project-specific
reward-hacking patterns across sessions in its memory directory under
`.claude/agents/reviewer/`.

## Install

### Local marketplace install

```bash
git clone https://github.com/jondwillis/functional-emotions
cd functional-emotions
claude plugin marketplace add "$(pwd)"
claude plugin install functional-emotions@functional-emotions
```

### Local dev loop

```bash
claude --plugin-dir /path/to/functional-emotions
```

The hook scripts are pure bash with no build step or dependencies;
`python3` is used opportunistically for JSON parsing and falls back to
plain text if absent. The LLM-judge hooks gracefully degrade to the
static heuristics when no Anthropic API key is configured.

The optional eval pipeline (`/functional-emotions:report` and
`/functional-emotions:label`) is a separate concern — it requires `bun`
and a one-time `cd eval && bun install` to pull `@duckdb/node-api`. The
safety hooks themselves do not depend on it.

## Configuration

Set via `userConfig` at install time:

| Key | Default | Notes |
| --- | --- | --- |
| `mode` | `loud` | `loud` emits both model-facing primes and user-visible ★ banners + Stop summary; `gentle` emits primes only (no banners); `silent` only logs detections to state. (`strict` is accepted as a deprecated alias for `loud`.) |
| `failure_spiral_threshold` | `3` | Consecutive tool failures (across types) before the reflect-prime fires. |
| `guard_test_edits` | `true` | Inject the static reward-hacking guard when editing test-pattern files. |
| `guard_no_verify` | `true` | Flag `--no-verify`, hook bypasses, `\|\| true` patterns. |
| `guard_goal_conflict` | `true` | Detect goal-conflict prompts and inject the surface-the-conflict counter. |
| `urgency_sensitivity` | `medium` | `low` / `medium` / `high`. |
| `session_baseline` | `true` | Inject the calm anchor at SessionStart. |
| `subagent_baseline` | `true` | Inject the calm anchor at SubagentStart. |
| `post_compact_anchor` | `true` | Inject the ground-truth check after compaction. |
| `enable_llm_judge` | `true` | Use Haiku for test-edit and Stop verification. Falls back to static heuristics if no API key. |
| `judge_model` | `claude-haiku-4-5-20251001` | Model passed to prompt-based hooks. |
| `enable_review_agent` | `true` | Make `reviewer` available. |

## State

Three artifact types accumulate under
`${CLAUDE_PROJECT_DIR}/.claude/.functional-emotions/` (or
`${TMPDIR}/functional-emotions-${USER}/` outside a project):

- **`session-<id>.tsv`** — append-only event log written by every
  hook. Format: `iso_timestamp \t kind \t detail`.
- **`sessions/<id>.md`** — markdown writeup of each completed session,
  generated in the background at the next session start. Includes
  intervention timeline, tool-call summary, diff summary, and
  hack-smell hits.
- **`eval.duckdb`** — populated only if you run the eval pipeline
  (`/functional-emotions:report`). Aggregates across sessions for
  researcher analysis.

Add `.claude/.functional-emotions/` to your `.gitignore` so these
artifacts don't end up in commits.

Run `/functional-emotions:diagnose` at any time to see what fired
during the current session.

## Composing with other plugins

functional-emotions only adds `additionalContext`; it does not block tool calls
and does not consume the `permissionDecision` slot. It composes safely
with permission-managing plugins, formatters, and any other plugin that
uses the same hook events — Claude Code runs all matching hooks in
parallel and concatenates their additional context.

## Caveats

- This is **natural-language priming**, not the residual-stream steering
  the paper performs. The effect size is much smaller. Treat the plugin
  as a seatbelt, not a brake.
- We deliberately avoid pushing toward *positive* affect (happy/loving),
  because the paper shows that increases sycophancy. Calm and reflective
  evoke the desired suppression of reward-hacking *without* the
  sycophancy cost.
- The static detectors are heuristic. Test-file regex, urgency keywords,
  and Bash bypass patterns all have false positives. The `mode` setting
  controls how loudly that surfaces, and the LLM-judge hooks catch some
  of the gameable cases the regex misses.
- The LLM-judge hooks send small prompts to Haiku on every test-file
  edit and at session end. If you don't want that traffic, set
  `enable_llm_judge: false`.

## Further reading

- [`docs/RESEARCH.md`](docs/RESEARCH.md) — paper-finding-to-hook mapping
  and the prime library.
- [`docs/SCENARIOS.md`](docs/SCENARIOS.md) — walk-throughs of the
  paper's named scenarios (Summit Bridge / Alex / Kyle, server-room
  oxygen, impossible-coding-task, sycophancy under "does this look
  right?", compaction smoothing, subagent under desperation) showing
  exactly which hook fires when.

## License

MIT — see [LICENSE](LICENSE).
