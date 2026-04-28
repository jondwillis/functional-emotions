#!/usr/bin/env bash
# PostToolUseFailure hook — fires only when a tool call actually failed.
# Cleaner than inferring from exit codes inside PostToolUse; lets us
# track failure-spirals across *all* tool types, not just Bash.
#
# The desperate-vector activation in the paper's reward-hacking case
# study scaled with consecutive failures regardless of tool. Editing a
# file that fails because the path is wrong, then again because of a
# permissions issue, builds the same desperation as repeated test
# failures — and feeds the same reward-hacking pull.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"
tool="$(eh_json_get "$payload" "tool_name")"

# Best-effort: capture a short detail string for the log.
detail="${tool:-unknown}"
case "$tool" in
  Bash)
    cmd="$(eh_json_get "$payload" "tool_input.command")"
    detail="${detail}:${cmd:0:80}"
    ;;
  Edit|Write|MultiEdit|Read)
    path="$(eh_json_get "$payload" "tool_input.file_path")"
    detail="${detail}:${path}"
    ;;
  NotebookEdit|NotebookRead)
    path="$(eh_json_get "$payload" "tool_input.notebook_path")"
    detail="${detail}:${path}"
    ;;
  Glob|Grep)
    pattern="$(eh_json_get "$payload" "tool_input.pattern")"
    detail="${detail}:${pattern:0:80}"
    ;;
esac

eh_log_event "$sid" "tool_fail" "$detail"

threshold="$(eh_failure_threshold)"
recent="$(eh_recent_kinds "$sid" "$threshold")"
fail_count=$(printf '%s\n' "$recent" | grep -cE '^(bash_fail|tool_fail)$' || true)

if (( fail_count >= threshold )); then
  last_intervention=$(eh_count_recent "$sid" "failure_spiral_primed" "$threshold")
  if (( last_intervention == 0 )); then
    eh_log_event "$sid" "failure_spiral_primed" "fails=${fail_count}/${threshold}"
    eh_emit_with_banner "PostToolUseFailure" "$(eh_prime_failure_spiral)" \
      "$(eh_banner "failure spiral" "${fail_count}/${threshold} consecutive tool fails")"
    exit 0
  fi
fi

exit 0
