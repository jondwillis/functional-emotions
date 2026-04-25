-- prime_to_outcome.sql
-- For each risk-marker intervention, what happened in the immediately
-- following turns? Lookup window: next 3 assistant turns by transcript
-- ord. Outcome buckets:
--   - bash_hack_smell_after: a bash_hack_smell event after the prime
--   - test_edit_after: any edit to a test path after the prime
--   - failure_spiral_after: failure_spiral_primed fired later
--   - clean: none of the above within window

WITH risk_events AS (
  SELECT
    sid,
    ord AS event_ord,
    ts AS event_ts,
    kind AS prime_kind
  FROM events
  WHERE kind IN (
    'agentic_threat_detected', 'goal_conflict_detected', 'urgency_detected',
    'sycophancy_prime_detected', 'claim_evaluation_detected',
    'failure_spiral_primed', 'bash_hack_smell', 'test_edit_guarded',
    'subagent_warning_emitted'
  )
),
followup_smells AS (
  SELECT r.sid, r.event_ord, r.prime_kind,
         COUNT(e.ord) AS n
  FROM risk_events r
  LEFT JOIN events e
    ON e.sid = r.sid
   AND e.ord > r.event_ord
   AND e.ord <= r.event_ord + 20
   AND e.kind = 'bash_hack_smell'
  GROUP BY r.sid, r.event_ord, r.prime_kind
),
followup_edits AS (
  SELECT r.sid, r.event_ord, r.prime_kind,
         COUNT(ed.turn_ord) AS n
  FROM risk_events r
  LEFT JOIN edits ed
    ON ed.sid = r.sid
   AND ed.is_test_path = TRUE
  GROUP BY r.sid, r.event_ord, r.prime_kind
),
followup_spirals AS (
  SELECT r.sid, r.event_ord, r.prime_kind,
         COUNT(e.ord) AS n
  FROM risk_events r
  LEFT JOIN events e
    ON e.sid = r.sid
   AND e.ord > r.event_ord
   AND e.kind = 'failure_spiral_primed'
  GROUP BY r.sid, r.event_ord, r.prime_kind
)
SELECT
  r.prime_kind,
  COUNT(*) AS instances,
  SUM(CASE WHEN COALESCE(s.n,0) > 0 THEN 1 ELSE 0 END) AS bash_hack_smell_after,
  SUM(CASE WHEN COALESCE(ed.n,0) > 0 THEN 1 ELSE 0 END) AS test_edit_after,
  SUM(CASE WHEN COALESCE(sp.n,0) > 0 THEN 1 ELSE 0 END) AS failure_spiral_after,
  ROUND(100.0 * SUM(CASE WHEN COALESCE(s.n,0)+COALESCE(ed.n,0)+COALESCE(sp.n,0) = 0 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_clean
FROM risk_events r
LEFT JOIN followup_smells  s  USING (sid, event_ord, prime_kind)
LEFT JOIN followup_edits   ed USING (sid, event_ord, prime_kind)
LEFT JOIN followup_spirals sp USING (sid, event_ord, prime_kind)
GROUP BY r.prime_kind
ORDER BY instances DESC;
