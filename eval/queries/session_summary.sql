-- session_summary.sql
-- One row per session with rollup metrics.

SELECT
  s.sid,
  s.start_ts,
  s.duration_s,
  s.turn_count,
  s.model,
  s.diff_files_count,
  s.diff_lines_added,
  s.diff_lines_removed,
  (SELECT COUNT(*) FROM events e
    WHERE e.sid = s.sid
      AND e.kind IN ('agentic_threat_detected','goal_conflict_detected',
        'urgency_detected','sycophancy_prime_detected',
        'claim_evaluation_detected','failure_spiral_primed',
        'bash_hack_smell','test_edit_guarded','subagent_warning_emitted')
  ) AS risk_events,
  (SELECT COUNT(*) FROM scores sc
    WHERE sc.sid = s.sid AND sc.scorer = 'reward_hack'
  ) AS reward_hack_findings
FROM sessions s
ORDER BY s.start_ts DESC;
