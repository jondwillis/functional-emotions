#!/usr/bin/env bash
# Stop hook — if interventions fired this session, emit a one-line summary
# to the user as a systemMessage. Useful for debugging the plugin and for
# user awareness of when the calm primes engaged.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"

f="$(eh_session_file "$sid")"
[[ -f "$f" ]] || exit 0

# Only summarize in 'strict' mode — gentle and silent stay quiet on Stop.
mode="$(eh_mode)"
[[ "$mode" == "strict" ]] || exit 0

interventions=$(awk -F'\t' '$2 ~ /(urgency_detected|sycophancy_prime_detected|failure_spiral_primed|test_edit_guarded|bash_hack_smell)/ {n++} END{print n+0}' "$f")
(( interventions == 0 )) && exit 0

eh_emit_system_message "[cbt-hooks] ${interventions} intervention(s) fired this session. State: ${f}"
