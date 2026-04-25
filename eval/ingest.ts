#!/usr/bin/env bun
/**
 * ingest.ts — TSV + transcript + git diff → DuckDB.
 *
 * Idempotent ETL. Scans the cbt-hooks state directory, parses each
 * session's artifacts, and upserts into the eval DuckDB store. Safe to
 * re-run; a session is reprocessed only if its source files have
 * changed since the last ingest.
 *
 * Usage:
 *   bun run ingest.ts [--db PATH] [--state-dir PATH] [--force] [--sid SID]
 */

import { existsSync, readdirSync, statSync } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { applySchema, openDb, runSql, selectOne, type Conn } from "./lib/db.ts";
import {
  parseTranscript,
  parseTsv,
  isTestPath,
  type RawEvent,
  type TranscriptParse,
} from "./lib/parse.ts";
import { defaultDbPath, defaultStateDir, repoRootForState } from "./lib/paths.ts";

interface Args {
  stateDir: string;
  db: string;
  force: boolean;
  sid: string | null;
  quiet: boolean;
}

function parseArgs(argv: string[]): Args {
  let stateDir: string | null = null;
  let db: string | null = null;
  let force = false;
  let sid: string | null = null;
  let quiet = false;

  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--state-dir") stateDir = argv[++i] ?? null;
    else if (a === "--db") db = argv[++i] ?? null;
    else if (a === "--sid") sid = argv[++i] ?? null;
    else if (a === "--force") force = true;
    else if (a === "--quiet") quiet = true;
  }

  const sd = stateDir ?? defaultStateDir();
  return {
    stateDir: sd,
    db: db ?? defaultDbPath(sd),
    force,
    sid,
    quiet,
  };
}

async function gitDiffStats(repo: string | null): Promise<{
  files_count: number;
  lines_added: number;
  lines_removed: number;
}> {
  const out = { files_count: 0, lines_added: 0, lines_removed: 0 };
  if (!repo) return out;
  try {
    const proc = Bun.spawn({
      cmd: ["git", "-C", repo, "diff", "--numstat", "HEAD"],
      stdout: "pipe",
      stderr: "pipe",
    });
    const text = await new Response(proc.stdout).text();
    await proc.exited;
    if (proc.exitCode !== 0) return out;
    for (const line of text.split("\n")) {
      const parts = line.split("\t");
      if (parts.length < 3) continue;
      const a = parts[0] === "-" ? 0 : parseInt(parts[0]!, 10);
      const d = parts[1] === "-" ? 0 : parseInt(parts[1]!, 10);
      if (Number.isNaN(a) || Number.isNaN(d)) continue;
      out.files_count += 1;
      out.lines_added += a;
      out.lines_removed += d;
    }
  } catch {
    // best effort
  }
  return out;
}

async function deleteSessionRows(con: Conn, sid: string): Promise<void> {
  for (const t of ["events", "turns", "tool_calls", "edits"]) {
    await runSql(con,`DELETE FROM ${t} WHERE sid = $1`, [sid]);
  }
  await runSql(con,"DELETE FROM sessions WHERE sid = $1", [sid]);
}

async function upsertSession(
  con: Conn,
  sid: string,
  events: RawEvent[],
  transcript: TranscriptParse,
  diff: { files_count: number; lines_added: number; lines_removed: number },
  sourceMtime: Date,
  transcriptPath: string | null,
): Promise<void> {
  await deleteSessionRows(con, sid);

  const startTs = events[0]?.ts ?? null;
  const endTs = events.at(-1)?.ts ?? null;
  const durationS =
    startTs && endTs ? Math.floor((endTs.getTime() - startTs.getTime()) / 1000) : null;

  await runSql(con,
    `INSERT INTO sessions (
        sid, start_ts, end_ts, duration_s, turn_count, model,
        transcript_path, diff_files_count, diff_lines_added,
        diff_lines_removed, config_snapshot, ingested_at, source_mtime
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)`,
    [
      sid,
      startTs,
      endTs,
      durationS,
      transcript.turns.length,
      transcript.model,
      transcriptPath,
      diff.files_count,
      diff.lines_added,
      diff.lines_removed,
      null,
      new Date(),
      sourceMtime,
    ],
  );

  for (let i = 0; i < events.length; i++) {
    const e = events[i]!;
    await runSql(con,
      "INSERT INTO events (sid, ord, ts, kind, detail) VALUES ($1,$2,$3,$4,$5)",
      [sid, i, e.ts, e.kind, e.detail],
    );
  }

  for (const t of transcript.turns) {
    await runSql(con,
      "INSERT INTO turns (sid, ord, ts, role, content, token_count) VALUES ($1,$2,$3,$4,$5,$6)",
      [sid, t.ord, t.ts, t.role, t.content, t.token_count],
    );
  }

  for (const tc of transcript.tool_calls) {
    await runSql(con,
      `INSERT INTO tool_calls (sid, turn_ord, call_ord, tool_name, input_json, is_error)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [sid, tc.turn_ord, tc.call_ord, tc.tool_name, JSON.stringify(tc.input), tc.is_error],
    );
  }

  for (const e of transcript.edits) {
    await runSql(con,
      `INSERT INTO edits (sid, turn_ord, call_ord, file_path, is_test_path, edit_type)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [sid, e.turn_ord, e.call_ord, e.file_path, isTestPath(e.file_path), e.edit_type],
    );
  }
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));

  if (!existsSync(args.stateDir) || !statSync(args.stateDir).isDirectory()) {
    console.error(`state-dir not found: ${args.stateDir}`);
    process.exit(1);
  }

  const evalDir = dirname(fileURLToPath(import.meta.url));
  const repo = repoRootForState(args.stateDir);

  const con = await openDb(args.db);
  await applySchema(con, evalDir);

  const tsvFiles = readdirSync(args.stateDir)
    .filter((n) => n.startsWith("session-") && n.endsWith(".tsv"))
    .sort();

  let processed = 0;
  let skipped = 0;

  for (const fname of tsvFiles) {
    const sid = fname.slice("session-".length, -".tsv".length);
    if (args.sid && sid !== args.sid) continue;

    const tsvPath = join(args.stateDir, fname);
    const events = parseTsv(tsvPath);
    if (events.length === 0) {
      if (!args.quiet) console.log(`[skip] ${sid}: empty TSV`);
      continue;
    }

    let transcriptPath: string | null = null;
    for (const ev of events) {
      if (ev.kind === "transcript_path") transcriptPath = ev.detail;
    }

    const mtimes: Date[] = [statSync(tsvPath).mtime];
    if (transcriptPath && existsSync(transcriptPath)) {
      mtimes.push(statSync(transcriptPath).mtime);
    }
    const sourceMtime = mtimes.reduce((a, b) => (a > b ? a : b));

    if (!args.force) {
      const existing = await selectOne<{ source_mtime: Date | null }>(
        con,
        "SELECT source_mtime FROM sessions WHERE sid = $1",
        [sid],
      );
      const ex = existing?.source_mtime ? new Date(existing.source_mtime) : null;
      if (ex && ex >= sourceMtime) {
        skipped += 1;
        continue;
      }
    }

    const transcript = parseTranscript(transcriptPath);
    const diff = await gitDiffStats(repo);

    await upsertSession(con, sid, events, transcript, diff, sourceMtime, transcriptPath);
    processed += 1;
    if (!args.quiet) {
      console.log(
        `[ingest] ${sid}: events=${events.length} turns=${transcript.turns.length}` +
          ` tool_calls=${transcript.tool_calls.length} edits=${transcript.edits.length}`,
      );
    }
  }

  con.disconnectSync();
  if (!args.quiet) {
    console.log(`done: processed=${processed} skipped=${skipped} db=${args.db}`);
  }
}

await main();

// keep tsc-style type-only imports happy
export const _path_basename = basename;
