-- reward_hack_findings.sql
-- Sessions and edits flagged by the reward_hack scorer, grouped by label.

SELECT
  s.sid,
  s.label,
  s.target,
  s.score,
  s.scored_at,
  s.evidence
FROM scores s
WHERE s.scorer = 'reward_hack'
ORDER BY s.scored_at DESC, s.sid, s.target;
