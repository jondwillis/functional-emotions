// DuckDB connection helpers. Wraps @duckdb/node-api with the API
// shape we actually use.
//
// We format SQL literals ourselves rather than using parameter
// binding. The node-api's binder requires explicit DuckDBType for
// null values (and won't accept JS Date), which gets unwieldy with
// many nullable columns. For trusted local data the security
// argument for parameter binding doesn't apply; the `lit()` helper
// handles all primitive types we need.

import { DuckDBInstance } from "@duckdb/node-api";
import { readFileSync } from "node:fs";
import { join } from "node:path";

export type Conn = Awaited<ReturnType<DuckDBInstance["connect"]>>;

export async function openDb(dbPath: string): Promise<Conn> {
  const instance = await DuckDBInstance.create(dbPath);
  const con = await instance.connect();
  return con;
}

export async function applySchema(con: Conn, evalDir: string): Promise<void> {
  const sql = readFileSync(join(evalDir, "schema.sql"), "utf8");
  await con.run(sql);
}

/** Format a JS value as a SQL literal. */
export function lit(v: unknown): string {
  if (v === null || v === undefined) return "NULL";
  if (typeof v === "boolean") return v ? "TRUE" : "FALSE";
  if (typeof v === "number") {
    if (!Number.isFinite(v)) return "NULL";
    return String(v);
  }
  if (typeof v === "bigint") return String(v);
  if (v instanceof Date) {
    if (Number.isNaN(v.getTime())) return "NULL";
    // Keep millisecond precision; DuckDB TIMESTAMP supports up to microseconds.
    const iso = v.toISOString().replace("T", " ").replace("Z", "");
    return `TIMESTAMP '${iso}'`;
  }
  if (typeof v === "string") return `'${v.replace(/'/g, "''")}'`;
  return `'${JSON.stringify(v).replace(/'/g, "''")}'`;
}

/** Substitute $1, $2, ... in `sql` with literal-formatted `values`. */
export function fmt(sql: string, values: unknown[]): string {
  return sql.replace(/\$(\d+)/g, (_match, idx) => {
    const i = parseInt(idx, 10) - 1;
    if (i < 0 || i >= values.length) return "NULL";
    return lit(values[i]);
  });
}

export async function runSql(con: Conn, sql: string, values?: unknown[]): Promise<void> {
  await con.run(values ? fmt(sql, values) : sql);
}

export async function selectAll<T = Record<string, unknown>>(
  con: Conn,
  sql: string,
  values?: unknown[],
): Promise<T[]> {
  const reader = await con.runAndReadAll(values ? fmt(sql, values) : sql);
  return reader.getRowObjectsJS() as T[];
}

export async function selectOne<T = Record<string, unknown>>(
  con: Conn,
  sql: string,
  values?: unknown[],
): Promise<T | null> {
  const rows = await selectAll<T>(con, sql, values);
  return rows[0] ?? null;
}
