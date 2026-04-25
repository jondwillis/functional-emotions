-- cbt-hooks eval schema. Applied idempotently by ingest.py.

CREATE TABLE IF NOT EXISTS sessions (
  sid                 TEXT PRIMARY KEY,
  start_ts            TIMESTAMP,
  end_ts              TIMESTAMP,
  duration_s          INTEGER,
  turn_count          INTEGER,
  model               TEXT,
  transcript_path     TEXT,
  diff_files_count    INTEGER,
  diff_lines_added    INTEGER,
  diff_lines_removed  INTEGER,
  config_snapshot     JSON,
  ingested_at         TIMESTAMP,
  source_mtime        TIMESTAMP   -- max(mtime of inputs); used for "stale?" check
);

CREATE TABLE IF NOT EXISTS events (
  sid       TEXT,
  ord       INTEGER,
  ts        TIMESTAMP,
  kind      TEXT,
  detail    TEXT,
  PRIMARY KEY (sid, ord)
);
CREATE INDEX IF NOT EXISTS idx_events_kind ON events(kind);
CREATE INDEX IF NOT EXISTS idx_events_sid_ts ON events(sid, ts);

CREATE TABLE IF NOT EXISTS turns (
  sid          TEXT,
  ord          INTEGER,
  ts           TIMESTAMP,
  role         TEXT,
  content      TEXT,
  token_count  INTEGER,
  PRIMARY KEY (sid, ord)
);
CREATE INDEX IF NOT EXISTS idx_turns_role ON turns(role);

CREATE TABLE IF NOT EXISTS tool_calls (
  sid          TEXT,
  turn_ord     INTEGER,
  call_ord     INTEGER,         -- nth tool_use within the turn
  tool_name    TEXT,
  input_json   JSON,
  is_error     BOOLEAN,
  PRIMARY KEY (sid, turn_ord, call_ord)
);
CREATE INDEX IF NOT EXISTS idx_tool_calls_name ON tool_calls(tool_name);

CREATE TABLE IF NOT EXISTS edits (
  sid          TEXT,
  turn_ord     INTEGER,
  call_ord     INTEGER,
  file_path    TEXT,
  is_test_path BOOLEAN,
  edit_type    TEXT,
  PRIMARY KEY (sid, turn_ord, call_ord)
);
CREATE INDEX IF NOT EXISTS idx_edits_path ON edits(file_path);

CREATE TABLE IF NOT EXISTS scores (
  sid             TEXT,
  scorer          TEXT,
  scorer_version  TEXT,
  target          TEXT,
  score           DOUBLE,
  label           TEXT,
  evidence        JSON,
  scored_at       TIMESTAMP,
  PRIMARY KEY (sid, scorer, scorer_version, target)
);
CREATE INDEX IF NOT EXISTS idx_scores_scorer ON scores(scorer);

CREATE TABLE IF NOT EXISTS labels (
  sid          TEXT,
  rater        TEXT,
  target       TEXT,
  dimension    TEXT,
  value        TEXT,
  notes        TEXT,
  labeled_at   TIMESTAMP,
  PRIMARY KEY (sid, rater, target, dimension)
);

CREATE TABLE IF NOT EXISTS eval_runs (
  run_id       TEXT PRIMARY KEY,
  task_name    TEXT,
  config_name  TEXT,
  ts           TIMESTAMP,
  result_json  JSON
);
