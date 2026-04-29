// Plain-text mirror of the DuckDB `labels` table.
//
// DuckDB holds the canonical query surface; this JSONL file holds the
// canonical durable copy. If eval.duckdb is deleted, restore-labels.ts
// rebuilds the table from this file. Append-only with latest-wins on
// the (sid, rater, target, dimension) key.

import { appendFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname } from "node:path";
import { selectAll, type Conn } from "./db.ts";

export interface LabelRow {
  v: number;
  sid: string;
  rater: string;
  target: string;
  dimension: string;
  value: string;
  notes: string;
  labeled_at: string; // ISO 8601 UTC
}

const SCHEMA_VERSION = 1;

export function labelsJsonlPath(dbPath: string): string {
  return dirname(dbPath) + "/labels.jsonl";
}

export function appendLabelJsonl(
  path: string,
  row: Omit<LabelRow, "v">,
): void {
  const full: LabelRow = { v: SCHEMA_VERSION, ...row };
  mkdirSync(dirname(path), { recursive: true });
  appendFileSync(path, JSON.stringify(full) + "\n", "utf8");
}

export function readLabelsJsonl(path: string): LabelRow[] {
  if (!existsSync(path)) return [];
  const text = readFileSync(path, "utf8");
  const rows: LabelRow[] = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    rows.push(JSON.parse(line) as LabelRow);
  }
  return rows;
}

// Latest-wins: walk in order, keep last row per (sid, rater, target, dimension).
export function dedupeLatest(rows: LabelRow[]): LabelRow[] {
  const map = new Map<string, LabelRow>();
  for (const r of rows) {
    map.set(`${r.sid}\t${r.rater}\t${r.target}\t${r.dimension}`, r);
  }
  return [...map.values()];
}

// One-shot bootstrap: if the JSONL file doesn't exist yet but the DB
// has labels, dump them so the next DB-delete is recoverable.
export async function bootstrapJsonlFromDb(
  con: Conn,
  path: string,
): Promise<number> {
  if (existsSync(path)) return 0;
  const rows = await selectAll<{
    sid: string;
    rater: string;
    target: string;
    dimension: string;
    value: string;
    notes: string | null;
    labeled_at: Date | string | null;
  }>(con, "SELECT sid, rater, target, dimension, value, notes, labeled_at FROM labels");
  if (rows.length === 0) return 0;
  for (const r of rows) {
    const labeledAt =
      r.labeled_at instanceof Date
        ? r.labeled_at.toISOString()
        : r.labeled_at
        ? new Date(r.labeled_at).toISOString()
        : new Date(0).toISOString();
    appendLabelJsonl(path, {
      sid: r.sid,
      rater: r.rater,
      target: r.target,
      dimension: r.dimension,
      value: r.value,
      notes: r.notes ?? "",
      labeled_at: labeledAt,
    });
  }
  return rows.length;
}
