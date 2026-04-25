-- intervention_frequency.sql
-- Per-kind event counts over time. Risk-marker kinds called out separately.

WITH risk_kinds AS (
  SELECT * FROM (VALUES
    ('agentic_threat_detected'),
    ('goal_conflict_detected'),
    ('urgency_detected'),
    ('sycophancy_prime_detected'),
    ('claim_evaluation_detected'),
    ('failure_spiral_primed'),
    ('bash_hack_smell'),
    ('test_edit_guarded'),
    ('subagent_warning_emitted')
  ) AS t(kind)
)
SELECT
  e.kind,
  COUNT(*) AS total_count,
  COUNT(DISTINCT e.sid) AS sessions_seen,
  ROUND(100.0 * COUNT(DISTINCT e.sid) / NULLIF((SELECT COUNT(*) FROM sessions), 0), 1) AS pct_of_sessions,
  MIN(e.ts) AS first_seen,
  MAX(e.ts) AS last_seen,
  CASE WHEN e.kind IN (SELECT kind FROM risk_kinds)
       THEN 'risk' ELSE 'routine' END AS category
FROM events e
GROUP BY e.kind
ORDER BY category DESC, total_count DESC;
