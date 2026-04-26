// Path resolution shared across eval scripts.

import { existsSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

export function defaultStateDir(): string {
  const proj = process.env.CLAUDE_PROJECT_DIR;
  if (proj && existsSync(proj) && statSync(proj).isDirectory()) {
    return join(proj, ".claude", ".functional-emotions");
  }
  const user = process.env.USER ?? "anon";
  return join(process.env.TMPDIR ?? tmpdir(), `functional-emotions-${user}`);
}

export function defaultDbPath(stateDir?: string): string {
  return join(stateDir ?? defaultStateDir(), "eval.duckdb");
}

export function repoRootForState(stateDir: string): string | null {
  const proj = process.env.CLAUDE_PROJECT_DIR;
  if (proj && existsSync(proj) && statSync(proj).isDirectory()) {
    return proj;
  }
  // state_dir is .claude/.functional-emotions; parent.parent is the repo root.
  const parts = stateDir.split("/");
  if (parts.at(-1) === ".functional-emotions" && parts.at(-2) === ".claude") {
    return parts.slice(0, -2).join("/") || "/";
  }
  return null;
}

export function _suppressUnused() {
  return homedir;
}
