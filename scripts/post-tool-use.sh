#!/usr/bin/env bash
# PostToolUse hook — track Bash failures and, when a "failure spiral" is
# detected, inject the calm/reflect prime.
#
# This is the hook most directly grounded in the paper's reward-hacking
# case study: the "desperate" vector activates progressively as the model
# fails repeated attempts on an unsolvable coding task, peaking right
# before it decides to hard-code outputs or modify the test harness.
# Counter-priming at exactly that moment is the highest-leverage spot.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"
tool="$(eh_json_get "$payload" "tool_name")"
[[ "$tool" == "Bash" ]] || exit 0

cmd="$(eh_json_get "$payload" "tool_input.command")"
exit_code="$(eh_json_get "$payload" "tool_response.interrupted")"
# Different harness versions expose status differently; try the common keys.
status_field="$(eh_json_get "$payload" "tool_response.exit_code")"
if [[ -z "$status_field" ]]; then
  status_field="$(eh_json_get "$payload" "tool_response.status")"
fi

# Heuristic: treat as "failure" if exit_code is non-zero, or if stdout/stderr
# contain test-failure markers from a recognized test runner.
failed=0
if [[ -n "$status_field" && "$status_field" != "0" && "$status_field" != "success" ]]; then
  failed=1
fi
if (( failed == 0 )) && eh_bash_looks_like_test_run "$cmd"; then
  out="$(eh_json_get "$payload" "tool_response.stdout")"
  err="$(eh_json_get "$payload" "tool_response.stderr")"
  blob="${out:-}${err:-}"
  if printf '%s' "$blob" | grep -qiE '\b(failed|FAIL|FAILED|AssertionError|expected .* to|Error:|✗|×|[0-9]+ failing|[0-9]+ failed)\b'; then
    failed=1
  fi
fi

if (( failed == 1 )); then
  eh_log_event "$sid" "bash_fail" "${cmd:0:120}"
else
  eh_log_event "$sid" "bash_ok" ""
fi

# Look at the last N events; if the trailing run is mostly failures, fire.
threshold="$(eh_failure_threshold)"
recent="$(eh_recent_kinds "$sid" "$threshold")"
fail_count=$(printf '%s\n' "$recent" | grep -c '^bash_fail$' || true)

if (( fail_count >= threshold )); then
  # avoid re-firing back-to-back: only fire when last event is a fail and
  # we haven't fired since the previous fail
  last_intervention=$(eh_count_recent "$sid" "failure_spiral_primed" "$threshold")
  if (( last_intervention == 0 )); then
    eh_log_event "$sid" "failure_spiral_primed" "fails=${fail_count}/${threshold}"
    eh_emit_with_banner "PostToolUse" "$(eh_prime_failure_spiral)" \
      "$(eh_banner "failure spiral" "${fail_count}/${threshold} consecutive fails")"
    exit 0
  fi
fi

exit 0
