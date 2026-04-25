#!/usr/bin/env bash
# PostCompact hook — companion to pre-compact. Once compaction completes,
# inject a ground-truth-restoration prompt so the model actively scans
# the new summary for smoothing (failures collapsed into "in progress",
# user pushback dropped, assumptions promoted to facts).

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

if [[ "$(eh_post_compact_anchor)" != "true" ]]; then
  exit 0
fi

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"

eh_log_event "$sid" "post_compact" ""
eh_emit_additional_context "PostCompact" "$(eh_prime_post_compact)"
