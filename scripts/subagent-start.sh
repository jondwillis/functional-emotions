#!/usr/bin/env bash
# SubagentStart hook — propagate the calm anchor into newly spawned
# subagents. Subagents inherit none of the parent's primes today, and
# they typically run with a narrow task and fresh context — exactly the
# conditions under which the desperate vector activates most strongly
# (per the emotion-concepts paper's reward-hacking case study).

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

if [[ "$(eh_subagent_baseline)" != "true" ]]; then
  exit 0
fi

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"
agent_type="$(eh_json_get "$payload" "agent_type")"

eh_log_event "$sid" "subagent_start" "${agent_type:-unknown}"
eh_emit_additional_context "SubagentStart" "$(eh_prime_subagent_baseline)"
