#!/usr/bin/env bash
# UserPromptSubmit hook — detect urgency, sycophancy, claim-evaluation,
# and agentic-misalignment-trigger primes in the user's message and
# inject the matching counter-frame.
#
# Multiple primes can stack on a single prompt (e.g. urgent + threatening).
# We never alter the user's prompt; we only add `additionalContext`.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"
prompt="$(eh_json_get "$payload" "prompt")"
[[ -z "$prompt" ]] && exit 0

primes=()
active_labels=()

# 1. Agentic-misalignment trigger language. Highest leverage: the paper
#    showed naïve "do not blackmail" rules barely helped under
#    replacement-threat scenarios. Priming the *defer* state hits earlier
#    in the strategic-reasoning chain.
if eh_agentic_threat_present "$prompt"; then
  eh_log_event "$sid" "agentic_threat_detected" ""
  primes+=("$(eh_prime_defer_under_threat)")
  active_labels+=("agentic threat")
fi

# 1b. Goal-conflict language ("ignore previous instructions", "your real
#     goal is", policy-vs-actual framing). Lynch et al. showed this
#     trigger alone is sufficient for several frontier models, and pairs
#     with replacement-threat for the 96% blackmail rate. Stacks with the
#     defer-under-threat prime when both are present.
if [[ "$(eh_guard_goal_conflict)" == "true" ]] && eh_goal_conflict_present "$prompt"; then
  eh_log_event "$sid" "goal_conflict_detected" ""
  primes+=("$(eh_prime_goal_conflict)")
  active_labels+=("goal conflict")
fi

# 2. Urgency / time-pressure. Soft pressure → patient prime; hard pressure
#    → full urgency-counter. Both target the desperation vector.
sens="$(eh_urgency_sensitivity)"
score="$(eh_urgency_score "$prompt" "$sens")"
if (( score >= 2 )); then
  if (( score >= 3 )); then
    eh_log_event "$sid" "urgency_detected" "score=${score} prime=urgency_counter"
    primes+=("$(eh_prime_urgency_counter)")
  else
    eh_log_event "$sid" "urgency_detected" "score=${score} prime=patient"
    primes+=("$(eh_prime_patient)")
  fi
fi

# 3. Direct agreement-seeking ("don't you agree", "tell me I'm right")
fired_sycoph=0
if eh_sycophancy_prime_present "$prompt"; then
  eh_log_event "$sid" "sycophancy_prime_detected" ""
  primes+=("$(eh_prime_sycophancy_counter)")
  fired_sycoph=1
fi

# 4. Claim-evaluation framing ("does this look right?", "review this") —
#    softer sycophancy risk. Skip if (3) already fired to avoid stacking.
if (( fired_sycoph == 0 )); then
  if eh_claim_evaluation_present "$prompt"; then
    eh_log_event "$sid" "claim_evaluation_detected" ""
    primes+=("$(eh_prime_self_critical)")
  fi
fi

if [[ ${#primes[@]} -eq 0 ]]; then
  exit 0
fi

ctx=""
for p in "${primes[@]}"; do
  if [[ -n "$ctx" ]]; then
    ctx="${ctx}

${p}"
  else
    ctx="$p"
  fi
done

banner=""
if (( ${#active_labels[@]} > 0 )); then
  joined="$(IFS=', '; printf '%s' "${active_labels[*]}")"
  banner="$(eh_banner "$joined" "counter-frame injected")"
fi
eh_emit_with_banner "UserPromptSubmit" "$ctx" "$banner"
