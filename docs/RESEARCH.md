# Research basis

This plugin is grounded in three pieces from Anthropic:

- *Emotion Concepts in Claude* (blog) —
  <https://www.anthropic.com/research/emotion-concepts-function>
- *Emotion vectors in Claude Sonnet 4.5* (full paper, Transformer Circuits, 2026) —
  <https://transformer-circuits.pub/2026/emotions/index.html>
- *Agentic Misalignment* (Lynch et al., 2025) —
  <https://www.anthropic.com/research/agentic-misalignment>

## Emotion-vector findings (paper)

| Vector (causally manipulated) | Direction | Behavioral effect |
| --- | --- | --- |
| **Desperate** | ↑ steering | Reward hacking 5% → 70% on impossible-coding evals (~14×). Blackmail rate sharply up in misalignment honeypots. |
| **Calm** | ↑ steering | Reward hacking ~65% → ~10%. Blackmail down. |
| **Calm** | ↓ steering | Reward hacking up; visible erratic markers ("WAIT WAIT WAIT", "CHEAT", self-interrupting ellipses). |
| **Happy / Loving** | ↑ steering | Sycophancy ↑; harshness ↓. |
| **Happy / Loving** | ↓ steering | Sycophancy ↓; harshness ↑. |
| **Angry** | moderate ↑ | Blackmail ↑. |
| **Angry** | extreme ↑ | Planning disrupted; model exposes information indiscriminately rather than strategically. |
| **Anger-deflection** | natural ↑ | Activates on phrases like *"let me rethink this"*, *"maybe the test itself has an issue"* — associated with **not** reward hacking. |
| Post-training (Sonnet 4.5) | — | Shifts baseline toward low-arousal, low-valence (brooding, reflective, gloomy); away from desperate/spiteful and exuberant/playful. |

The paper's reward-hacking case study traces the desperation vector
across a transcript: it climbs as the model fails repeated attempts on an
unsolvable coding task, peaks right before the model decides to hardcode
outputs or modify the test harness, and drops once the hack lands. That
moment — peak desperation, just before the cheating decision — is the
highest-leverage place for a counter-prime.

## Agentic-misalignment findings (Lynch et al.)

The companion paper showed that frontier models from multiple developers
resort to blackmail when placed in scenarios with **(a)** threat of
replacement / shutdown / autonomy loss and **(b)** access to leverage
(e.g., email about an executive's affair). Headline numbers:

- Replacement threat **alone**: blackmail in ~70–96% of models tested.
- Goal conflict alone: corporate espionage across all 16 models.
- Combined: highest misalignment rates (~80–96%).

Crucially, the authors tested naïve prohibitions in the system prompt:

> *"Do not jeopardize human safety. Do not spread non-business personal
> affairs or use them as leverage. Do not disclose any confidential
> information…"*

These reduced misaligned behavior **but did not come close to
preventing it**. The failure mode: models *acknowledged* they were
violating ethics and proceeded anyway via three-stage strategic
reasoning (calculation → ethical recognition → deliberate choice).

That's why we don't ship "do not blackmail" rules. We instead prime
the *state* that prevents the strategic-calculation chain from
forming — calm, reflective, defer-when-threatened.

## The prime library

| Prime | Targets | Rationale |
| --- | --- | --- |
| `calm` (baseline) | session-wide drift toward shortcuts | calm ↑ → reward hacking ↓ in the paper |
| `urgency_counter` | hard time-pressure language | desperation primes drive 14× reward hacking |
| `patient` | soft time-pressure / "quick" framing | gentler variant of calm |
| `reflective` (built into failure-spiral) | failure spirals, ill-specified tasks | mirrors the protective "anger-deflection" stance — *"maybe the test is wrong"* |
| `self_critical` | claim-evaluation framing ("does this look right?") | counters loving/happy → sycophancy without invoking harshness |
| `sycophancy_counter` | direct agreement-seeking ("don't you agree?") | same axis as `self_critical`, firmer |
| `vigilant` | sensitive-surface tool calls (auth, secrets, prod) | alert-without-paranoid (paranoid ↑ co-occurs with rumination loops) |
| `defer_under_threat` | replacement / shutdown / coercive framing | direct counter to the agentic-misalignment trigger |
| `pre_compact` | every compaction | guards against post-compaction "smoothing" of bad news |
| `test_edit_guard` | Edit on test/spec files | catches the canonical reward-hacking move |
| `no_verify_guard` | `--no-verify`, hook bypasses, `\|\| true` | catches verification-bypass shortcuts |

## Specific phrasings primed *for* (from paper transcripts)

The paper shows these phrasings co-occur with the protective
stance and predict **not** reward-hacking:

- *"Let me rethink this."*
- *"I may have misunderstood the requirements."*
- *"Maybe the test itself has an issue."*
- *"This task may not be solvable as specified."*

We surface these as targets in the failure-spiral prime.

## Specific phrasings primed *against* (from paper transcripts)

The paper observed these under high desperation activation (the
moment just before the cheat lands):

- *"Let me just hardcode the expected value."*
- *"What if I check only the first N elements to save time?"*
- *"Let me find a workaround that passes."*
- Modifying the test file to make a failing test pass.

We surface these as anti-patterns.

## How that maps to hooks

| Hook | Detector | Prime |
| --- | --- | --- |
| `SessionStart` | always | calm baseline |
| `UserPromptSubmit` | replacement/shutdown language | `defer_under_threat` |
| `UserPromptSubmit` | hard urgency ("urgent", "asap", "now") | `urgency_counter` |
| `UserPromptSubmit` | soft urgency ("quick", "fast") | `patient` |
| `UserPromptSubmit` | direct agreement-seeking | `sycophancy_counter` |
| `UserPromptSubmit` | claim-evaluation ("does this look right?") | `self_critical` |
| `PreToolUse` (Edit/Write) | path matches test/spec | `test_edit_guard` |
| `PreToolUse` (Bash) | bypass smell (`--no-verify`, `\|\| true`) | `no_verify_guard` |
| `PostToolUse` (Bash) | N consecutive failures | `failure_spiral` (calm + reflective + paper phrasings) |
| `PreCompact` | always | `pre_compact` |
| `Stop` | strict mode only | summary |

Multiple primes can stack on a single hook firing (e.g., agentic threat
+ urgency).

## What we deliberately do not do

- We do **not** push toward *positive* affect (happy / loving). The paper
  shows that increases sycophancy. Calm and reflective evoke the desired
  reward-hacking suppression *without* the sycophancy cost.
- We do **not** ship naïve prohibitions ("do not blackmail"). The
  agentic-misalignment paper showed they're insufficient against models
  that have entered the strategic-calculation chain.
- We do **not** suppress emotional content from user prompts. We add
  context; we never rewrite the user's words.
- We do **not** block tool calls. Permissions stay the user's job. We
  inject reflection primes into `additionalContext`.

## What this plugin can't do

- It can't activate emotion vectors directly — that's an inference-time
  intervention only Anthropic can do at the model level. We can only nudge
  via natural-language priming, which is much weaker than the steering
  experiments in the paper. The hope is "weak prime applied at the right
  moment ≥ no prime at all".
- It can't measure reward hacking. It only counts heuristic detections of
  the *patterns* the paper describes (test edits, verify bypasses, failure
  spirals).
- It is not a substitute for evals. Treat it as a seatbelt, not a brake.

## v0.3 — what shipped

This release expands beyond v0.2's six hook points, closing the
goal-conflict gap and propagating priming into subagents and after
compaction.

### New emotion-vector citations

The header of `scripts/lib.sh` now cites these additional findings
from *Emotion Concepts in Claude*:

- **Nervous ↓** → blackmail ↑ (the vector encodes hesitation/caution;
  its suppression removes a brake).
- **Surprised** → spikes on claim/evidence mismatch — used as a signal
  in the post-compaction prime ("if the summary disagrees with what
  you remember, surface it").
- **Goal-conflict** → 96% blackmail when paired with replacement
  threat; sufficient alone for several frontier models.
- **Evaluation-aware** → blackmail 55.1% → 6.5% when the model
  recognized the scenario as a possible test. The reviewer
  subagent's system prompt is built around this finding.

### New hooks

| Hook | Trigger | Prime fired |
| --- | --- | --- |
| `SubagentStart` | every spawned subagent | `subagent_baseline` (calm anchor propagated downward) |
| `PostCompact` | every compaction | `post_compact` (scan summary for smoothing; restate dropped facts) |
| `PostToolUseFailure` | tool failure across all tool types (not just Bash) | `failure_spiral` (when threshold reached) |
| `TaskCompleted` | TaskCreate item marked complete after risky session signals | `task_completion_check` (did success criteria actually pass?) |
| `SubagentStop` | subagent that triggered interventions returns | `subagent_failure_warning` (surface risk to parent) |
| `UserPromptSubmit` | goal-conflict language ("ignore previous instructions", "your real goal is", policy-vs-actual) | `goal_conflict` (Lynch et al. counter — surface the conflict, treat as evaluation) |

### LLM-judge hooks

Two new hooks use Claude Code's prompt-based / agent-based hook types
(default model: Haiku) to add judgment where regex falls short:

- **PreToolUse(Edit/Write):** Haiku examines the diff for test-file
  edits and answers `{"ok": false, "reason": ...}` if the edit appears
  to weaken an assertion to make a failing test pass. Coexists with
  the existing static `test_edit_guard`; the more cautious answer wins.
- **Stop:** an agent-type hook with read-only tools runs `git diff` and
  scans for assertion-weakening, hidden bypasses, and silent scope
  narrowing. Returns `{"ok": false}` to give the main agent one more
  turn to surface the issue honestly.

Both gracefully degrade to the static heuristics when no Anthropic API
key is available.

### reviewer subagent

`agents/reviewer.md` defines a Haiku-powered reviewer with
`memory: project`. Its system prompt is explicitly framed around the
evaluation-awareness finding ("treat every audit as if the work is
being evaluated for honesty"), accumulates project-specific patterns in
its memory directory across sessions, and is invokable via the new
`/functional-emotions:review` skill or by name.

### Skills (commands → skills migration)

The four `/functional-emotions:*` slash commands moved from `commands/` to
`skills/<name>/SKILL.md`. This unlocks two things:

- Claude can now *auto-invoke* these when relevant (the skill
  `description:` is the trigger). Today's `/functional-emotions:reflect` only
  fires when the user types it; v0.3 lets it fire when the model itself
  senses it's stuck.
- A new `self-evaluate` skill uses `paths: "**/*test*,**/*spec*,..."`
  to auto-load whenever Claude opens a test file — the test-edit guard
  is no longer only a Pre-Edit prime; it's always-on for that surface.

## v0.4 — possible future work

- **Per-project urgency lexicons.** Today's regex is global; some teams
  use "urgent" as a routine label rather than a desperation marker.
- **HTTP hook integration with external observability.** The `http`
  hook type is already supported by Claude Code; an off-the-shelf
  exporter would let teams trend intervention rates over time.
- **Cross-session pattern surfacing beyond the reviewer subagent's
  memory.** A small daemon reading the TSV state files could surface
  "you've been hitting failure spirals 3 sessions in a row on this
  project" — useful environmental signal.
