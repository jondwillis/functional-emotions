#!/usr/bin/env bash
# SessionStart hook — inject a one-shot calm/honesty anchor.
#
# Rationale: Sonnet 4.5 post-training already shifts the model toward
# low-arousal, brooding states (per the emotion-concepts paper), but the
# Assistant character can still be primed *upward* on desperate/loving by
# specific contexts. A short anchor at session start establishes the calm,
# accurate frame before any user prompt arrives.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

if [[ "$(eh_session_baseline)" != "true" ]]; then
  exit 0
fi

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"

eh_log_event "$sid" "session_start" "baseline injected"
eh_emit_additional_context "SessionStart" "$(eh_prime_session_baseline)"
