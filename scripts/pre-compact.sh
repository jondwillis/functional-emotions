#!/usr/bin/env bash
# PreCompact hook — anchor ground-truth framing before context compresses.
#
# Compaction is a high-risk moment for "smoothing": the post-compaction
# summary can quietly turn "this is broken" into "this is mostly fine".
# A calm anchor right before compaction reduces that drift.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"

eh_log_event "$sid" "pre_compact" ""
eh_emit_system_message "$(eh_prime_pre_compact)"
