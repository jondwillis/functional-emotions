#!/usr/bin/env bash
# SessionStart hook — inject a one-shot calm/honesty anchor and
# (in the background) generate writeups for any prior sessions that
# haven't been audited yet.
#
# Rationale: Sonnet 4.5 post-training already shifts the model toward
# low-arousal, brooding states (per the emotion-concepts paper), but the
# Assistant character can still be primed *upward* on desperate/loving by
# specific contexts. A short anchor at session start establishes the calm,
# accurate frame before any user prompt arrives.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

payload="$(eh_read_stdin)"
sid="$(eh_json_get "$payload" "session_id")"
[[ -z "$sid" ]] && sid="default"

# Snapshot the active config as JSON so post-hoc analysis can compare
# loud / gentle / silent runs (and other knobs) without re-deriving from env.
# Logged unconditionally — captures the config even when the baseline gate
# below short-circuits (e.g. session_baseline=false).
config_json="$(eh_config_snapshot_json)"
[[ -n "$config_json" ]] && eh_log_event "$sid" "config_snapshot" "$config_json"

# Background writeups for unaudited prior sessions. Detached so the hook
# returns immediately; the writeups land whenever they finish. We
# sequence them in a single subshell rather than fanning out in parallel
# so a backlog of unaudited sessions doesn't spike load.
unaudited="$(eh_unaudited_sessions "$sid")"
if [[ -n "$unaudited" ]]; then
  (
    while IFS= read -r prior_sid; do
      [[ -z "$prior_sid" ]] && continue
      bash "${CLAUDE_PLUGIN_ROOT}/scripts/post-session-writeup.sh" "$prior_sid" >/dev/null 2>&1 || true
    done <<< "$unaudited"
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
fi

if [[ "$(eh_session_baseline)" != "true" ]]; then
  exit 0
fi

eh_log_event "$sid" "session_start" "baseline injected"
eh_emit_additional_context "SessionStart" "$(eh_prime_session_baseline)"
