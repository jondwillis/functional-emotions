#!/usr/bin/env bash
# TaskCompleted hook — fires when the model marks a TaskCreate item as
# complete. Reward-hacking shows up at task boundaries: the moment of
# declaring "done" is the canonical place to weaken assertions, narrow
# scope, or skip verification. A short honesty prime here catches that
# at exactly the right time.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"

# Only fire if recent activity included signals that suggest reward-hack
# risk (a recent failure-spiral, a test-edit guard, or a bash hack
# smell). Unconditional firing would be noise.
recent="$(eh_recent_kinds "$sid" 20)"
risky=0
if printf '%s\n' "$recent" | grep -qE '^(failure_spiral_primed|test_edit_guarded|bash_hack_smell|tool_fail|bash_fail)$'; then
  risky=1
fi

(( risky == 0 )) && exit 0

eh_log_event "$sid" "task_completed_check" ""
eh_emit_additional_context "TaskCompleted" "$(eh_prime_task_completion_check)"
