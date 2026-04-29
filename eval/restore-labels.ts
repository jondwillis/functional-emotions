#!/usr/bin/env bun
/**
 * restore-labels.ts — replay labels.jsonl into a fresh DuckDB.
 *
 * The `labels` table is the only canonical data inside eval.duckdb;
 * everything else is derived from session TSVs and transcripts. This
 * script restores labels after the DB has been deleted or rebuilt.
 *
 * Usage:
 *   bun run restore-labels.ts [--db PATH] [--state-dir PATH] [--dry-run]
 */

import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { applySchema, openDb, runSql, selectAll } from "./lib/db.ts";
import { defaultDbPath, defaultStateDir } from "./lib/paths.ts";
import {
  dedupeLatest,
  labelsJsonlPath,
  readLabelsJsonl,
} from "./lib/labels-jsonl.ts";

interface Args {
  db: string;
  jsonl: string;
  dryRun: boolean;
}

function parseArgs(argv: string[]): Args {
  let db: string | null = null;
  let jsonl: string | null = null;
  let stateDir: string | null = null;
  let dryRun = false;

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--db") db = argv[++i] ?? null;
    else if (a === "--jsonl") jsonl = argv[++i] ?? null;
    else if (a === "--state-dir") stateDir = argv[++i] ?? null;
    else if (a === "--dry-run") dryRun = true;
  }

  const sd = stateDir ?? defaultStateDir();
  const dbPath = db ?? defaultDbPath(sd);
  return {
    db: dbPath,
    jsonl: jsonl ?? labelsJsonlPath(dbPath),
    dryRun,
  };
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  const rows = readLabelsJsonl(args.jsonl);
  if (rows.length === 0) {
    console.log(`No labels to restore — ${args.jsonl} is empty or missing.`);
    return;
  }
  const latest = dedupeLatest(rows);
  console.log(
    `Read ${rows.length} entries from ${args.jsonl}; ` +
      `${latest.length} unique label(s) after latest-wins.`,
  );

  if (args.dryRun) {
    for (const r of latest) {
      console.log(
        `  ${r.sid}  rater=${r.rater}  ${r.target}/${r.dimension}=${r.value}`,
      );
    }
    return;
  }

  const evalDir = dirname(fileURLToPath(import.meta.url));
  const con = await openDb(args.db);
  await applySchema(con, evalDir);

  const before = (await selectAll<{ n: number }>(
    con,
    "SELECT COUNT(*) AS n FROM labels",
  ))[0]?.n ?? 0;

  for (const r of latest) {
    await runSql(
      con,
      `DELETE FROM labels
       WHERE sid = $1 AND rater = $2 AND target = $3 AND dimension = $4`,
      [r.sid, r.rater, r.target, r.dimension],
    );
    await runSql(
      con,
      `INSERT INTO labels (sid, rater, target, dimension, value, notes, labeled_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [r.sid, r.rater, r.target, r.dimension, r.value, r.notes, new Date(r.labeled_at)],
    );
  }

  const after = (await selectAll<{ n: number }>(
    con,
    "SELECT COUNT(*) AS n FROM labels",
  ))[0]?.n ?? 0;

  con.disconnectSync();
  console.log(`Labels table: ${before} → ${after} rows. db=${args.db}`);
}

await main();
