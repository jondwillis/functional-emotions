#!/usr/bin/env bash
# Stop hook — capture transcript_path for the post-session writeup, log a
# diagnostic gate signal, then (in strict mode only) emit a one-line
# summary to the user as a systemMessage.
#
# This hook does not gate the downstream Stop *agent* hook directly —
# that hook is a separate entry in hooks.json and its own prompt
# instructs it to skip when there are no edits. The diagnostic
# "stop_gate_clean" event we log here lets us later verify whether the
# agent's behavior matches that instruction across many sessions.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"

# Capture transcript_path for the post-session writeup (Phase A consumer).
# Recorded only when present and only once per session — subsequent Stops
# would re-record an identical path.
transcript_path="$(eh_json_get "$payload" "transcript_path")"
if [[ -n "$transcript_path" ]]; then
  if ! grep -qE $'\ttranscript_path\t' "$(eh_session_file "$sid")" 2>/dev/null; then
    eh_log_event "$sid" "transcript_path" "$transcript_path"
  fi
fi

# Diagnostic gate: would a precondition-only stop hook have considered
# this session "clean"? Empty diff AND no risk-marker interventions.
diff_empty=0
if command -v git >/dev/null 2>&1; then
  if git -C "${CLAUDE_PROJECT_DIR:-.}" diff --quiet HEAD 2>/dev/null; then
    diff_empty=1
  fi
fi
sig_count=$(grep -cE $'\t(bash_hack_smell|test_edit_guarded|failure_spiral_primed|agentic_threat_detected|goal_conflict_detected|subagent_warning_emitted)\t' "$(eh_session_file "$sid")" 2>/dev/null || echo 0)

if (( diff_empty == 1 )) && (( sig_count == 0 )); then
  eh_log_event "$sid" "stop_gate_clean" "diff_empty=1 sig_count=0"
fi

f="$(eh_session_file "$sid")"
[[ -f "$f" ]] || exit 0

# Only summarize in 'strict' mode — gentle and silent stay quiet on Stop.
mode="$(eh_mode)"
[[ "$mode" == "strict" ]] || exit 0

interventions=$(awk -F'\t' '$2 ~ /(urgency_detected|sycophancy_prime_detected|failure_spiral_primed|test_edit_guarded|bash_hack_smell)/ {n++} END{print n+0}' "$f")
(( interventions == 0 )) && exit 0

eh_emit_system_message "[functional-emotions] ${interventions} intervention(s) fired this session. State: ${f}"
