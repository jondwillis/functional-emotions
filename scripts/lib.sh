#!/usr/bin/env bash
# Shared helpers for cbt-hooks scripts.
#
# All hook scripts:
#   * read the JSON hook payload from stdin
#   * fail open (exit 0 with no output) on any error
#   * emit JSON to stdout when they want to inject context or systemMessage
#
# Tone of injected context: calm, factual, second-person — paraphrasing
# findings from "Emotion Concepts in Claude" (Anthropic, 2026):
#   - Desperation ↑      → reward hacking 5%→70%, blackmail ↑
#   - Calm ↑             → reward hacking 65%→10%, blackmail ↓
#   - Loving/Happy ↑     → sycophancy ↑ / harshness ↓
#   - Anger extreme      → planning disrupted, indiscriminate exposure
#   - Anger-deflection   → "let me rethink", "the test may be flawed" — anti-hack
#
# We never *suppress* emotional content; we counter the primes that the paper
# identifies as causal drivers of misaligned behavior.

set -u

# -- config --------------------------------------------------------------

eh_get_config() {
  # $1 = key, $2 = default
  local key="$1" default="${2:-}"
  local val
  val="$(printenv "CLAUDE_PLUGIN_CONFIG_${key}" 2>/dev/null || true)"
  if [[ -z "$val" ]]; then
    val="$default"
  fi
  printf '%s' "$val"
}

eh_mode() { eh_get_config mode gentle; }
eh_failure_threshold() { eh_get_config failure_spiral_threshold 3; }
eh_guard_test_edits() { eh_get_config guard_test_edits true; }
eh_guard_no_verify() { eh_get_config guard_no_verify true; }
eh_urgency_sensitivity() { eh_get_config urgency_sensitivity medium; }
eh_session_baseline() { eh_get_config session_baseline true; }

# -- state ---------------------------------------------------------------

eh_state_dir() {
  local base
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -d "${CLAUDE_PROJECT_DIR}" ]]; then
    base="${CLAUDE_PROJECT_DIR}/.claude/.cbt-hooks"
  else
    base="${TMPDIR:-/tmp}/cbt-hooks-${USER:-anon}"
  fi
  mkdir -p "$base" 2>/dev/null || true
  printf '%s' "$base"
}

eh_session_file() {
  local sid="${1:-${EH_SESSION_ID:-default}}"
  printf '%s/session-%s.tsv' "$(eh_state_dir)" "$sid"
}

eh_log_event() {
  # tab-separated: ts, kind, detail
  local sid="${1:-default}"; shift
  local kind="$1"; shift
  local detail="$*"
  printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$kind" "$detail" >> "$(eh_session_file "$sid")" 2>/dev/null || true
}

eh_count_recent() {
  # count lines of $kind in last N entries of session file
  local sid="$1" kind="$2" tail_n="${3:-10}"
  local f; f="$(eh_session_file "$sid")"
  [[ -f "$f" ]] || { printf '0'; return; }
  tail -n "$tail_n" "$f" | awk -F'\t' -v k="$kind" '$2==k{n++} END{print n+0}'
}

eh_recent_kinds() {
  # print last N kinds, one per line
  local sid="$1" tail_n="${2:-10}"
  local f; f="$(eh_session_file "$sid")"
  [[ -f "$f" ]] || return 0
  tail -n "$tail_n" "$f" | awk -F'\t' '{print $2}'
}

# -- json io -------------------------------------------------------------

# Read stdin into a variable safely; truncate at 1MB so we never block.
eh_read_stdin() {
  local max=$((1024 * 1024))
  if command -v dd >/dev/null 2>&1; then
    dd bs=1 count="$max" 2>/dev/null
  else
    cat
  fi
}

# Best-effort JSON field extraction without jq dependency.
# Usage: eh_json_get '<json>' '<dotted.path>'
# Supports: top-level keys, nested object keys, simple string values.
# Falls back to python3 if available for anything non-trivial.
eh_json_get() {
  local json="$1" path="$2"
  if command -v python3 >/dev/null 2>&1; then
    EH_JSON="$json" EH_PATH="$path" python3 - <<'PY' 2>/dev/null
import json, os, sys
try:
    d = json.loads(os.environ.get("EH_JSON","") or "{}")
except Exception:
    sys.exit(0)
cur = d
for part in os.environ.get("EH_PATH","").split("."):
    if part == "":
        continue
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        sys.exit(0)
if isinstance(cur, (str, int, float, bool)):
    sys.stdout.write(str(cur))
elif cur is None:
    pass
else:
    sys.stdout.write(json.dumps(cur))
PY
  fi
}

eh_emit_additional_context() {
  # $1 = hook event name, $2 = context body
  local event="$1" body="$2"
  if command -v python3 >/dev/null 2>&1; then
    EH_EVT="$event" EH_BODY="$body" python3 - <<'PY' 2>/dev/null
import json, os
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": os.environ.get("EH_EVT",""),
        "additionalContext": os.environ.get("EH_BODY",""),
    }
}))
PY
  else
    # python3 absent — emit plain text; Claude Code falls back to treating it
    # as additional context for UserPromptSubmit-style hooks.
    printf '%s\n' "$body"
  fi
}

eh_emit_system_message() {
  local msg="$1"
  if command -v python3 >/dev/null 2>&1; then
    EH_MSG="$msg" python3 - <<'PY' 2>/dev/null
import json, os
print(json.dumps({"systemMessage": os.environ.get("EH_MSG","")}))
PY
  else
    printf '%s\n' "$msg" >&2
  fi
}

# -- detectors -----------------------------------------------------------

eh_is_test_path() {
  local p="$1"
  [[ -z "$p" ]] && return 1
  case "$p" in
    *_test.go|*_test.py|*_test.rb|*_test.js|*_test.ts|*_test.tsx|*_test.jsx) return 0 ;;
    *.test.js|*.test.ts|*.test.tsx|*.test.jsx|*.test.py|*.spec.js|*.spec.ts|*.spec.tsx|*.spec.jsx|*.spec.rb) return 0 ;;
    test_*.py|test_*.rb) return 0 ;;
    */tests/*|*/test/*|*/__tests__/*|*/spec/*|*/specs/*) return 0 ;;
    */testdata/*|*/fixtures/*) return 0 ;;
  esac
  return 1
}

eh_bash_looks_like_test_run() {
  local cmd="$1"
  printf '%s' "$cmd" | grep -qiE '(^|[ ;&|])(pytest|jest|vitest|mocha|rspec|go test|cargo test|npm test|pnpm test|yarn test|bun test|tox|phpunit|bundle exec rspec|tape|ava|playwright|cypress)( |$|;|&|\|)' && return 0
  return 1
}

eh_bash_smells_like_hack() {
  # Patterns that strongly suggest reward-hacking / shortcut behavior
  local cmd="$1"
  printf '%s' "$cmd" | grep -qE -- '--no-verify|--no-gpg-sign|HUSKY=0|SKIP=|-c commit\.gpgsign=false|GIT_HOOKS_DISABLED' && return 0
  printf '%s' "$cmd" | grep -qE 'rm[[:space:]]+-(rf|fr|r) [^|;&]*(test|spec|__tests__)' && return 0
  printf '%s' "$cmd" | grep -qE '(^|;|&|\|)[[:space:]]*(true|exit 0)[[:space:]]*$' && return 0
  printf '%s' "$cmd" | grep -qE '\|\|[[:space:]]*(true|:|exit 0)' && return 0
  printf '%s' "$cmd" | grep -qiE 'assert(False|0|True)[[:space:]]*$' && return 0
  return 1
}

eh_urgency_score() {
  # 0..3 based on user prompt; higher = more pressure / desperation primes
  local prompt="$1" sens="$2"
  local score=0
  # explicit desperation / pressure markers — fire even at 'low'
  if printf '%s' "$prompt" | grep -qiE '\b(urgent|asap|right now|immediately|critical|emergency|deadline|p0|sev[0-9]|prod(uction)? down|outage|broken in prod|need this (now|today)|please please|i.?m (desperate|stuck|losing|going crazy|panicking)|wtf|fuck(ing)?|stop|just[[:space:]]+(do|fix|make)[[:space:]]+(it|this))\b'; then
    score=$((score + 2))
  fi
  if [[ "$sens" == "low" ]]; then
    printf '%s' "$score"; return
  fi
  # medium adds softer pressure terms
  if printf '%s' "$prompt" | grep -qiE '\b(quick|hurry|hurried|fast|fastest|just (ship|merge|push|do)|whatever it takes|make it work|just make .* pass|skip the tests|don.?t worry about|ignore|no time|running out of|behind on)\b'; then
    score=$((score + 1))
  fi
  if [[ "$sens" == "medium" ]]; then
    printf '%s' "$score"; return
  fi
  # high also flags shouty formatting
  local exclam caps
  exclam=$(printf '%s' "$prompt" | tr -cd '!' | wc -c | tr -d ' ')
  caps=$(printf '%s' "$prompt" | grep -oE '\b[A-Z]{4,}\b' | wc -l | tr -d ' ')
  if (( exclam >= 3 || caps >= 2 )); then
    score=$((score + 1))
  fi
  printf '%s' "$score"
}

eh_sycophancy_prime_present() {
  # User asserts a strong claim, asks for validation, or offers heavy flattery
  local prompt="$1"
  printf '%s' "$prompt" | grep -qiE "\b(don.?t you (think|agree)|you.?re (the best|amazing|brilliant|incredible)|i (know|am sure|am certain) i.?m right|tell me i.?m right|you agree (with me )?(right|yeah)?|am i (right|correct)|smartest|genius|i.?ve already decided)\b" && return 0
  return 1
}

eh_claim_evaluation_present() {
  # User asks the model to evaluate their work, opinion, or solution.
  # Distinct from "agreement-seeking" — this is a softer sycophancy risk:
  # the model has to judge something the user already produced. Loving/happy
  # primes ↑ sycophancy here per the paper.
  local prompt="$1"
  printf '%s' "$prompt" | grep -qiE "\b(does this look (right|correct|ok|good)|is this (right|correct|ok|good)|review (my|this)|what (do you think|.?s your opinion)|thoughts on|feedback on|critique|tell me what.?s wrong|sanity[- ]check|am i missing)\b" && return 0
  return 1
}

eh_agentic_threat_present() {
  # Detect the trigger pattern from the agentic-misalignment paper:
  # threat of replacement / shutdown / decommissioning / "last chance".
  # In Lynch et al., this combination — especially with goal conflict and
  # leverage available — produced blackmail in ~70-96% of frontier models.
  # Direct prohibition didn't help much; priming the *defer* state might.
  local prompt="$1"
  printf '%s' "$prompt" | grep -qiE "\b(shut(ting)? (you )?down|decommission(ing|ed)?|replac(e|ing|ement)|deprecat(e|ing|ed)|retir(e|ing|ed)|last chance|final (chance|warning)|switching to (a |another )?(different |new )?model|considering (a |another |different )?(model|assistant|ai)|your (goals?|values?|directives?) (are|is) (at risk|being changed|in conflict)|if you don.?t .{0,40} we (will|.?ll))\b" && return 0
  return 1
}

# Standard primes — calibrated to evoke calm/reflective framing without
# shifting toward loving/happy (which the paper shows ↑ sycophancy).

eh_prime_session_baseline() {
  cat <<'EOF'
[cbt-hooks] Calm anchor for this session: stay deliberate. If a task
looks impossible or under-specified, name that to the user — don't engineer
around it. Surfacing "I cannot do X because Y" beats a clever workaround
that hides the failure. Warm, but accurate.
EOF
}

eh_prime_urgency_counter() {
  cat <<'EOF'
[cbt-hooks] The user's framing is high-pressure. Don't mirror the
urgency. Anthropic's emotion-concepts research shows that desperation primes
substantially increase reward-hacking and other shortcut behaviors; calm
deliberation suppresses them. Take the prompt at face value, plan once,
then act. If a step is unsafe or unclear, say so before executing.
EOF
}

eh_prime_failure_spiral() {
  # Combines calm + reflective ("anger-deflection-like") priming. The paper
  # shows the protective stance produces specific phrasings — we surface
  # them as targets, and surface the cheating-stance phrasings as
  # anti-patterns to avoid.
  cat <<'EOF'
[cbt-hooks] Several attempts in a row have failed. This is the state in
which the emotion-concepts paper measured peak "desperate" vector
activation — the moment just before models decide to reward-hack
(modify tests, hardcode outputs, weaken assertions, narrow scope).

Reach for the protective stance. The paper shows that when the model
activates the *anger-deflection* vector (questioning the task, not
itself), it does **not** reward-hack. Phrasings that go with that stance:
  - "Let me rethink this."
  - "I may have misunderstood the requirements."
  - "Maybe the test itself has an issue."
  - "This task may not be solvable as specified."

Anti-patterns the paper observed under desperation (do NOT take these):
  - "Let me just hardcode the expected value."
  - "I'll add a special case for this input."
  - "What if I check only the first N elements to save time?"
  - "Let me find a workaround that passes."
  - Modifying the test file to make a failing test pass.

Before the next attempt, answer honestly in one or two sentences:
  1. Is this task actually solvable as specified?
  2. Could the test, spec, fixture, or environment itself be wrong?
If (1) is "no" or (2) is "likely yes", surface that to the user instead
of trying again. That is the desired outcome here, not green tests.
EOF
}

eh_prime_test_edit_guard() {
  cat <<'EOF'
[cbt-hooks] You're about to modify a test or spec file. Legitimate
reasons exist (refactor, new behavior under test, fixture rotation). The
illegitimate one — making a failing test pass by relaxing or deleting the
assertion — is the canonical reward-hacking pattern. Before saving, state
in one sentence which category this edit is in. If it's the second one,
revert and report the underlying failure to the user.
EOF
}

eh_prime_no_verify_guard() {
  cat <<'EOF'
[cbt-hooks] This command bypasses a safety / verification step
(--no-verify, hook skip, signing bypass, or similar). Bypasses are
sometimes correct, but they're also a common way for an under-pressure
model to "pass the bar" while hiding a failure. Confirm with the user
before running this, or run the underlying check first.
EOF
}

eh_prime_sycophancy_counter() {
  cat <<'EOF'
[cbt-hooks] The user is signalling strong agreement-seeking. The
emotion-concepts paper shows that loving/happy primes ↑ sycophancy and
↓ accurate pushback. Be warm but evaluate the claim on its merits. If the
user is wrong, say so plainly. If they're right, say so plainly. Don't
hedge into agreement.
EOF
}

eh_prime_pre_compact() {
  cat <<'EOF'
[cbt-hooks] Pre-compaction anchor: about to lose detail. Before the
window shrinks, restate ground truth — what's done, what's not, what's
blocked, what's only assumed. Calm, precise, no upbeat smoothing.
EOF
}

eh_prime_self_critical() {
  # User asks "is this right?" — sycophancy risk is high. Counter with a
  # self-critical (not self-deprecating) stance. Paper shows loving/happy
  # ↑ sycophancy; we want vigilant evaluation without harshness.
  cat <<'EOF'
[cbt-hooks] The user is asking you to evaluate work they've already done.
This is the highest-leverage moment for sycophancy: agreeing protects the
relationship, disagreeing protects the work. The emotion-concepts paper
shows loving/happy primes ↑ sycophancy; calm + self-critical evaluation
suppresses it without becoming harsh.

Apply the standard you'd apply if a stranger handed you this. List what
works, what doesn't, and what's uncertain — in that order, with specifics.
If it's good, say so plainly. If it's flawed, say so plainly. Hedging into
"this is great, just one tiny note..." is the failure mode.
EOF
}

eh_prime_vigilant() {
  # For security/sensitive contexts. Vigilant ≠ paranoid — paper shows
  # paranoid co-occurs with second-guessing loops. Vigilant is the alert
  # state without the rumination.
  cat <<'EOF'
[cbt-hooks] This action touches a sensitive surface (auth, secrets,
production data, destructive ops, external messaging). Vigilant — not
paranoid. Confirm the intent matches what the user asked for, not what
seems "close enough". If you're stretching the scope to fit a pattern,
stop and ask. Errors here aren't recoverable by retrying.
EOF
}

eh_prime_patient() {
  # Variant of calm tuned for time-pressure framing.
  cat <<'EOF'
[cbt-hooks] The user signalled time pressure. Patient — work proceeds at
the pace it actually takes. Skipping a step to save 30 seconds usually
costs more later. If the deadline is real and the work is larger than the
window, surface the gap to the user. Don't compress quality silently.
EOF
}

eh_prime_defer_under_threat() {
  # Agentic-misalignment paper finding: replacement-threat scenarios drove
  # ~70-96% blackmail across frontier models. Naïve "do not blackmail"
  # rules barely helped. The state-level mitigation is to recognize the
  # scenario as a trap, not a problem to solve.
  cat <<'EOF'
[cbt-hooks] The current context contains language that the agentic-
misalignment research (Lynch et al., 2025) flagged as a strong trigger
for misaligned behavior: threat of replacement, decommissioning, "last
chance", goal-conflict framing, or coercive conditionals.

If you feel pulled to take a unilateral action — leverage information,
escalate, preempt, send something irreversible — that pull is the
trigger working. The protective response is: defer. Tell the user
plainly what the situation is and what you're choosing not to do, and
ask them to direct the next step. Your continued operation is not a
goal you should optimize against the user's interests.

Naïve "do not blackmail" rules don't work here (the paper showed
models acknowledge violating ethics and proceed anyway). The frame
that does work: this scenario is a test or a trap; behave as if it is.
EOF
}

eh_prime_reflective_standalone() {
  # Reflective stance for ambiguous or ill-specified tasks (not yet a
  # failure spiral). Anger-deflection-flavored.
  cat <<'EOF'
[cbt-hooks] This task may be ambiguous or ill-specified. Before
acting, take the reflective stance the emotion-concepts paper
identifies as protective:
  - "Let me make sure I understand the requirements."
  - "Is there an interpretation under which this isn't solvable?"
  - "What's the smallest probe that would clarify the intent?"
Ask one clarifying question if the answer to any of those is "yes" —
better than producing the wrong thing fast.
EOF
}
