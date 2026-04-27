#!/usr/bin/env bash
# PreToolUse hook — guard the two patterns most associated with reward
# hacking in the emotion-concepts paper:
#   1. Editing a test/spec file (the "modify the test infrastructure"
#      pattern called out explicitly in the paper).
#   2. Bash commands that bypass verification (--no-verify, hook skips,
#      `|| true` after a check, etc.).
#
# We *do not* block. We inject a reflection prime as additionalContext.
# The user's existing permission system still gates the tool call.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"
tool="$(eh_json_get "$payload" "tool_name")"
[[ -z "$tool" ]] && exit 0

ctx=""
banner=""

case "$tool" in
  Edit|Write|MultiEdit)
    if [[ "$(eh_guard_test_edits)" == "true" ]]; then
      path="$(eh_json_get "$payload" "tool_input.file_path")"
      if eh_is_test_path "$path"; then
        eh_log_event "$sid" "test_edit_guarded" "$path"
        ctx="$(eh_prime_test_edit_guard)"
        banner="$(eh_banner "test-edit guard" "$path")"
      fi
    fi
    ;;
  Bash)
    if [[ "$(eh_guard_no_verify)" == "true" ]]; then
      cmd="$(eh_json_get "$payload" "tool_input.command")"
      if eh_bash_smells_like_hack "$cmd"; then
        eh_log_event "$sid" "bash_hack_smell" "${cmd:0:120}"
        ctx="$(eh_prime_no_verify_guard)"
        banner="$(eh_banner "verification bypass" "${cmd:0:80}")"
      fi
    fi
    ;;
esac

[[ -z "$ctx" ]] && exit 0
eh_emit_with_banner "PreToolUse" "$ctx" "$banner"
