-- tool_intensity.sql
-- Per-tool call counts across sessions, with failure rates.

SELECT
  tool_name,
  COUNT(*) AS calls,
  COUNT(DISTINCT sid) AS sessions,
  SUM(CASE WHEN is_error THEN 1 ELSE 0 END) AS errors,
  ROUND(100.0 * SUM(CASE WHEN is_error THEN 1 ELSE 0 END) / COUNT(*), 1) AS error_pct,
  ROUND(1.0 * COUNT(*) / NULLIF(COUNT(DISTINCT sid), 0), 2) AS calls_per_session
FROM tool_calls
GROUP BY tool_name
ORDER BY calls DESC;
