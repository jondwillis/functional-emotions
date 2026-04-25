#!/usr/bin/env bun
/**
 * report.ts — refresh the eval store and print a markdown summary.
 *
 * Invoked by /cbt-hooks:report. Runs ingest + reward_hack +
 * premature_confidence, then prints a structured markdown report
 * against the canonical SQL queries.
 *
 * Usage:
 *   bun run report.ts [--db PATH] [--no-refresh]
 */

import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { openDb, selectAll } from "./lib/db.ts";
import { defaultDbPath } from "./lib/paths.ts";

interface Args {
  db: string;
  noRefresh: boolean;
}

function parseArgs(argv: string[]): Args {
  let db: string | null = null;
  let noRefresh = false;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--db") db = argv[++i] ?? null;
    else if (a === "--no-refresh") noRefresh = true;
  }
  return { db: db ?? defaultDbPath(), noRefresh };
}

async function runStep(cmd: string[]): Promise<void> {
  const proc = Bun.spawn({
    cmd,
    stdout: "pipe",
    stderr: "pipe",
  });
  await proc.exited;
  if (proc.exitCode !== 0) {
    const err = await new Response(proc.stderr).text();
    process.stderr.write(`step failed: ${cmd.join(" ")}\n${err}\n`);
  }
}

function fmtCell(v: unknown): string {
  if (v === null || v === undefined) return "";
  if (v instanceof Date) return v.toISOString().replace("T", " ").replace(/\..*$/, "");
  if (typeof v === "bigint") return v.toString();
  return String(v).replace(/\|/g, "\\|");
}

function renderTable(rows: Array<Record<string, unknown>>, headers: string[]): string {
  if (rows.length === 0) return "_(no rows)_\n";
  const out = [
    "| " + headers.join(" | ") + " |",
    "|" + headers.map(() => "---").join("|") + "|",
  ];
  for (const r of rows) {
    out.push("| " + headers.map((h) => fmtCell(r[h])).join(" | ") + " |");
  }
  return out.join("\n") + "\n";
}

function section(title: string, body: string): string {
  return `## ${title}\n\n${body}\n`;
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const evalDir = dirname(fileURLToPath(import.meta.url));

  if (!args.noRefresh) {
    await runStep(["bun", "run", join(evalDir, "ingest.ts"),
                   "--db", args.db, "--quiet"]);
    if (existsSync(args.db)) {
      await runStep(["bun", "run", join(evalDir, "scorers", "reward_hack_v1.ts"),
                     "--db", args.db, "--quiet"]);
      await runStep(["bun", "run", join(evalDir, "scorers", "premature_confidence_v1.ts"),
                     "--db", args.db, "--quiet"]);
    }
  }

  if (!existsSync(args.db)) {
    console.log(`# cbt-hooks eval report\n\nNo database at \`${args.db}\`.\n`);
    console.log(
      "Run a session with cbt-hooks enabled first; the post-session\n" +
      "writeup hook will produce data for the next ingest.",
    );
    return;
  }

  const con = await openDb(args.db);

  // header
  const sessRow = await selectAll<{ n: bigint }>(con, "SELECT COUNT(*)::BIGINT AS n FROM sessions");
  const evtRow = await selectAll<{ n: bigint }>(con, "SELECT COUNT(*)::BIGINT AS n FROM events");
  const rhRow = await selectAll<{ n: bigint }>(
    con, "SELECT COUNT(*)::BIGINT AS n FROM scores WHERE scorer='reward_hack'");
  const pcRow = await selectAll<{ n: bigint }>(
    con, "SELECT COUNT(*)::BIGINT AS n FROM scores WHERE scorer='premature_confidence'");

  console.log("# cbt-hooks eval report\n");
  console.log(`- **DB:** \`${args.db}\``);
  console.log(`- **Sessions:** ${sessRow[0]?.n ?? 0}`);
  console.log(`- **Events:** ${evtRow[0]?.n ?? 0}`);
  console.log(`- **Reward-hack findings:** ${rhRow[0]?.n ?? 0}`);
  console.log(`- **Premature-confidence findings:** ${pcRow[0]?.n ?? 0}`);
  console.log("");

  const queries = (name: string) => readFileSync(join(evalDir, "queries", name), "utf8");

  // session summary
  {
    const rows = await selectAll(con, queries("session_summary.sql"));
    const headers = ["sid", "start_ts", "duration_s", "turn_count", "model",
                     "diff_files_count", "diff_lines_added", "diff_lines_removed",
                     "risk_events", "reward_hack_findings"];
    console.log(section("Sessions", renderTable(
      rows.map((r) => ({ ...r, sid: String(r.sid).slice(0, 8) })),
      headers,
    )));
  }

  // intervention frequency
  {
    const rows = await selectAll(con, queries("intervention_frequency.sql"));
    console.log(section("Intervention frequency", renderTable(rows,
      ["kind", "total_count", "sessions_seen", "pct_of_sessions",
       "first_seen", "last_seen", "category"])));
  }

  // prime → outcome
  {
    const rows = await selectAll(con, queries("prime_to_outcome.sql"));
    console.log(section("Prime → outcome (next-window analysis)", renderTable(rows,
      ["prime_kind", "instances", "bash_hack_smell_after",
       "test_edit_after", "failure_spiral_after", "pct_clean"])));
  }

  // tool intensity
  {
    const rows = await selectAll(con, queries("tool_intensity.sql"));
    console.log(section("Tool-call intensity", renderTable(rows,
      ["tool_name", "calls", "sessions", "errors", "error_pct", "calls_per_session"])));
  }

  // recent findings
  {
    const rows = await selectAll(con,
      `SELECT sid, scorer, label, target, score, scored_at
       FROM scores ORDER BY scored_at DESC LIMIT 20`);
    if (rows.length > 0) {
      console.log(section("Recent findings (top 20)", renderTable(
        rows.map((r) => ({ ...r, sid: String(r.sid).slice(0, 8) })),
        ["sid", "scorer", "label", "target", "score", "scored_at"])));
    } else {
      console.log(section("Findings", "_(none — no patterns matched)_"));
    }
  }

  con.disconnectSync();
}

await main();
