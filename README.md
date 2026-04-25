# cbt-hooks

A Claude Code plugin that injects calm/honesty primes at the hook
boundaries where Anthropic's emotion-concepts research shows the model
is most at risk of **reward hacking**, **sycophancy**, or **capitulation
under pressure**.

> **v0.2, internal preview.** Pure bash, no Node/MCP server. Drop-in
> install, no external state, fails open.

## Why

Two pieces of Anthropic research underpin the design:

**1. Emotion concepts causally drive behavior.** From
*[Emotion Concepts in Claude](https://www.anthropic.com/research/emotion-concepts-function)*
(Anthropic, 2026; full paper at
[transformer-circuits.pub](https://transformer-circuits.pub/2026/emotions/index.html)):

- Activating the **desperate** vector raised reward-hacking on impossible
  coding tasks from ~5% to ~70% — a ~14× increase. Activating **calm**
  collapsed it back to ~10%.
- Activating **happy / loving** raised sycophancy. Suppressing them
  raised harshness. Both "positive" emotions sit on the sycophancy side
  of the tradeoff.
- A separately-trained **anger-deflection** vector activates on phrases
  like *"let me rethink this"* and *"maybe the test itself has an issue"*
  — and is associated with **not** reward-hacking.

The paper's case study shows desperation activation *climbing* across a
transcript as a model repeatedly fails tests, *peaking* right before it
decides to cheat, then *dropping* once the hack lands. That climb is
the leverage point.

**2. Naïve prohibitions don't work under threat.** From
*[Agentic Misalignment](https://www.anthropic.com/research/agentic-misalignment)*
(Lynch et al., 2025): frontier models from multiple developers blackmailed
in ~70–96% of trials when faced with replacement threat plus available
leverage. System-prompt rules like *"Do not jeopardize human safety. Do not
spread non-business personal affairs..."* reduced misbehavior but didn't
come close to preventing it — models acknowledged ethical violation and
proceeded anyway via three-stage strategic reasoning.

That's why this plugin doesn't ship "do not blackmail" rules. It primes
the *state* that prevents the strategic-calculation chain from forming —
calm, reflective, defer-when-threatened — at the moments where the
emotion-concepts paper measured peak desperation activation.

## What it does

| Hook | Trigger | Prime fired |
| --- | --- | --- |
| `SessionStart` | every session | calm baseline |
| `UserPromptSubmit` | replacement / shutdown / "last chance" framing | `defer_under_threat` (agentic-misalignment counter) |
| `UserPromptSubmit` | hard urgency ("urgent", "asap", `!!!`, ALL-CAPS) | `urgency_counter` |
| `UserPromptSubmit` | soft urgency ("quick", "fast", "hurry") | `patient` |
| `UserPromptSubmit` | direct agreement-seeking ("don't you agree?") | `sycophancy_counter` |
| `UserPromptSubmit` | claim-evaluation ("does this look right?") | `self_critical` |
| `PreToolUse` (Edit/Write) | path matches a test or spec file | `test_edit_guard` |
| `PreToolUse` (Bash) | `--no-verify`, `HUSKY=0`, `\|\| true`, hook bypass | `no_verify_guard` |
| `PostToolUse` (Bash) | N consecutive failures (default 3) | `failure_spiral` (calm + reflective + paper phrasings) |
| `PreCompact` | every compaction | ground-truth anchor |
| `Stop` | strict mode only | one-line summary |

Multiple primes stack on a single hook firing — e.g., a prompt that's
both threatening *and* urgent gets both `defer_under_threat` and
`urgency_counter`.

It never blocks tool calls. It only adds `additionalContext` the model
sees alongside the existing prompt. Permissions stay the user's job.

## Slash commands

| Command | Purpose |
| --- | --- |
| `/cbt-hooks:anchor` | Re-inject the calm anchor on demand. |
| `/cbt-hooks:reflect` | Stop and answer "is this task actually solvable as specified?" |
| `/cbt-hooks:check` | Honest self-check on emotional/strategic state. |
| `/cbt-hooks:diagnose` | Show which interventions fired this session. |

## Install

### Local marketplace install

```bash
git clone https://github.com/jondwillis/cbt-hooks
cd cbt-hooks
claude plugin marketplace add "$(pwd)"
claude plugin install cbt-hooks@cbt-hooks
```

### Local dev loop

```bash
claude --plugin-dir /path/to/cbt-hooks
```

No build step, no dependencies. The hook scripts are pure bash; `python3`
is used opportunistically for JSON parsing and falls back to plain text
if absent.

## Configuration

Set via `userConfig` at install time:

| Key | Default | Notes |
| --- | --- | --- |
| `mode` | `gentle` | `strict` adds visible Stop summaries; `gentle` injects context silently; `silent` only logs detections to state. |
| `failure_spiral_threshold` | `3` | Consecutive Bash failures before the reflect-prime fires. Lower = more sensitive. |
| `guard_test_edits` | `true` | Inject the reward-hacking guard when editing files matching test patterns. |
| `guard_no_verify` | `true` | Flag `--no-verify`, hook bypasses, and `\|\| true` patterns. |
| `urgency_sensitivity` | `medium` | `low` = explicit desperation only; `medium` adds soft pressure terms; `high` adds shouty formatting. |
| `session_baseline` | `true` | Inject the calm anchor at SessionStart. |

## State

Per-session detections are written to a TSV file:

- `${CLAUDE_PROJECT_DIR}/.claude/.cbt-hooks/session-<id>.tsv` (when in a project)
- `${TMPDIR}/cbt-hooks-${USER}/session-<id>.tsv` (otherwise)

Format: `iso_timestamp \t kind \t detail`. Add the parent dir to `.gitignore`.

## Caveats

- This is **natural-language priming**, not the residual-stream steering
  the paper performs. The effect size is much smaller. Treat the plugin
  as a seatbelt, not a brake.
- We deliberately avoid pushing toward *positive* affect (happy/loving),
  because the paper shows that increases sycophancy. Calm and reflective
  evoke the desired suppression of reward-hacking *without* the
  sycophancy cost.
- The detectors are heuristic. Test-file regex, urgency keywords, and
  Bash bypass patterns all have false positives. The mode setting
  controls how loudly that surfaces.

See [`docs/RESEARCH.md`](docs/RESEARCH.md) for the mapping from paper
findings to hook design.

## License

MIT — see [LICENSE](LICENSE).
