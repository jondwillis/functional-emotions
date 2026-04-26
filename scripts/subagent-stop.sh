#!/usr/bin/env bash
# SubagentStop hook — when a subagent that triggered functional-emotions
# interventions returns to its parent, surface a short warning so the
# parent doesn't blindly consume the result. Subagent reasoning isn't
# visible to the parent; the functional-emotions log is the only signal that the
# subagent was operating under reward-hack pressure.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"

# Look at recent subagent-scoped events. If the subagent fired any of
# the risk patterns, warn the parent.
recent="$(eh_recent_kinds "$sid" 25)"
fired=0
if printf '%s\n' "$recent" | grep -qE '^(failure_spiral_primed|test_edit_guarded|bash_hack_smell)$'; then
  fired=1
fi

(( fired == 0 )) && exit 0

eh_log_event "$sid" "subagent_warning_emitted" ""
eh_emit_additional_context "SubagentStop" "$(eh_prime_subagent_failure_warning)"
