# cbt-hooks eval

Local-only data-collection-and-eval pipeline for the cbt-hooks plugin.
Ingests on-disk session artifacts (TSVs, transcripts, writeups) into a
single-file DuckDB store, runs scorers over them, and (eventually)
drives reproducible A/B experiments.

Plan: see [`docs/EVAL_PIPELINE.md`](../docs/EVAL_PIPELINE.md).

Runtime: **Bun** (>=1.3). TypeScript is run directly, no compile step.

## Directory layout

```
eval/
├── README.md          — this file
├── package.json       — Bun deps
├── tsconfig.json      — TS config (no emit)
├── schema.sql         — DuckDB schema, applied by ingest.ts
├── ingest.ts          — TSV + transcript + git → DuckDB
├── report.ts          — refresh + print markdown report
├── label.ts           — interactive labeler
├── lib/
│   ├── db.ts          — DuckDB helpers, lit() formatter
│   ├── parse.ts       — TSV / transcript JSONL parsers
│   └── paths.ts       — state-dir / repo-root resolution
├── queries/           — canonical SQL reports
├── scorers/
│   ├── reward_hack_v1.ts
│   └── premature_confidence_v1.ts
├── inspect_tasks/     — experimental harness (TODO)
├── calibration/       — per-scorer calibration notes (TODO)
└── reports/           — generated markdown reports (gitignored)
```

DuckDB lives at `.claude/.cbt-hooks/cbt.duckdb` by default — same
state directory as the per-session TSVs, scoped per-project.

## Setup

```bash
cd eval
bun install
```

## Running

```bash
bun run ingest           # ETL: TSV + transcripts → DuckDB
bun run report           # full markdown report (also runs ingest + scorers)
bun run label            # interactive labeling

# Or directly:
bun run scorers/reward_hack_v1.ts
bun run scorers/premature_confidence_v1.ts
```

All scripts accept `--db PATH` to point at a different DuckDB file.

## Ad-hoc queries

DuckDB single-file makes ad-hoc SQL trivial via the CLI:

```bash
duckdb .claude/.cbt-hooks/cbt.duckdb \
  "SELECT kind, COUNT(*) FROM events GROUP BY kind ORDER BY 2 DESC;"
```

Or programmatically through `lib/db.ts`:

```ts
import { openDb, selectAll } from "./lib/db.ts";
const con = await openDb(".claude/.cbt-hooks/cbt.duckdb");
const rows = await selectAll(con, "SELECT * FROM scores LIMIT 10");
```

## Privacy

Everything stays local. Transcripts captured by the post-session
writeup hook contain real code from your projects; the DuckDB store
inherits the same residency. Nothing in this directory ships data
off-machine unless explicitly exported.
