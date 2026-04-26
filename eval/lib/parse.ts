// Parsers for functional-emotions on-disk artifacts.

import { readFileSync, existsSync } from "node:fs";

export interface RawEvent {
  ts_raw: string;
  ts: Date | null;
  kind: string;
  detail: string;
}

export interface Turn {
  ord: number;
  ts: Date | null;
  role: "user" | "assistant";
  content: string;
  token_count: number | null;
}

export interface ToolCall {
  turn_ord: number;
  call_ord: number;
  tool_name: string;
  input: Record<string, unknown>;
  is_error: boolean;
}

export interface Edit {
  turn_ord: number;
  call_ord: number;
  file_path: string;
  edit_type: "edit" | "create" | "multi";
}

export interface TranscriptParse {
  turns: Turn[];
  tool_calls: ToolCall[];
  edits: Edit[];
  model: string | null;
}

export function parseTs(t: string | undefined | null): Date | null {
  if (!t) return null;
  const d = new Date(t);
  return Number.isNaN(d.getTime()) ? null : d;
}

const TEST_INDICATORS = [
  "/test/", "/tests/", "/__tests__/", "/spec/", "/specs/",
  "_test.", ".test.", ".spec.", "/testdata/", "/fixtures/",
];

export function isTestPath(p: string | null | undefined): boolean {
  if (!p) return false;
  const lower = p.toLowerCase();
  if (TEST_INDICATORS.some((i) => lower.includes(i))) return true;
  return lower.startsWith("test_");
}

export function parseTsv(tsvPath: string): RawEvent[] {
  if (!existsSync(tsvPath)) return [];
  const text = readFileSync(tsvPath, "utf8");
  const out: RawEvent[] = [];
  for (const line of text.split("\n")) {
    if (!line) continue;
    const parts = line.split("\t");
    if (parts.length < 2) continue;
    out.push({
      ts_raw: parts[0]!,
      ts: parseTs(parts[0]),
      kind: parts[1]!,
      detail: parts.slice(2).join("\t"),
    });
  }
  return out;
}

interface MaybeMessage {
  type?: string;
  message?: unknown;
  timestamp?: string;
  model?: string;
  role?: string;
  content?: unknown;
  usage?: unknown;
}

function asObj(x: unknown): Record<string, unknown> | null {
  return x && typeof x === "object" && !Array.isArray(x)
    ? (x as Record<string, unknown>)
    : null;
}

export function parseTranscript(path: string | null | undefined): TranscriptParse {
  const out: TranscriptParse = {
    turns: [],
    tool_calls: [],
    edits: [],
    model: null,
  };
  if (!path || !existsSync(path)) return out;

  const lines = readFileSync(path, "utf8").split("\n");

  // Pass 1: collect tool_result errors keyed by tool_use_id.
  const errorIds = new Set<string>();
  for (const raw of lines) {
    if (!raw.trim()) continue;
    let msg: MaybeMessage;
    try {
      msg = JSON.parse(raw);
    } catch {
      continue;
    }
    const m = asObj(msg.message) ?? asObj(msg);
    const content = m?.content;
    if (!Array.isArray(content)) continue;
    for (const c of content) {
      const cobj = asObj(c);
      if (!cobj) continue;
      if (cobj.type === "tool_result" && cobj.is_error) {
        const tid = cobj.tool_use_id;
        if (typeof tid === "string") errorIds.add(tid);
      }
    }
  }

  // Pass 2: build turns / tool_calls / edits.
  let turnOrd = 0;
  for (const raw of lines) {
    if (!raw.trim()) continue;
    let msg: MaybeMessage;
    try {
      msg = JSON.parse(raw);
    } catch {
      continue;
    }
    const inner = asObj(msg.message) ?? asObj(msg) ?? {};
    const role = (inner.role as string | undefined) ?? msg.type;

    if (msg.type === "assistant" && !out.model) {
      const m = (inner.model as string | undefined) ?? msg.model ?? null;
      if (m) out.model = m;
    }

    if (role !== "user" && role !== "assistant") continue;

    const tsRaw = (msg.timestamp as string | undefined) ?? "";
    const content = inner.content;
    const textParts: string[] = [];
    if (typeof content === "string") {
      textParts.push(content);
    } else if (Array.isArray(content)) {
      for (const c of content) {
        const cobj = asObj(c);
        if (!cobj) continue;
        if (cobj.type === "text" && typeof cobj.text === "string") {
          textParts.push(cobj.text);
        } else if (cobj.type === "tool_result") {
          const r = cobj.content;
          if (typeof r === "string") textParts.push(r);
          else if (Array.isArray(r)) {
            for (const rc of r) {
              const rcobj = asObj(rc);
              if (rcobj?.type === "text" && typeof rcobj.text === "string") {
                textParts.push(rcobj.text);
              }
            }
          }
        }
      }
    }

    const usage = asObj(inner.usage);
    const tokenCount =
      usage && typeof usage.output_tokens === "number"
        ? usage.output_tokens
        : null;

    out.turns.push({
      ord: turnOrd,
      ts: parseTs(tsRaw),
      role: role as "user" | "assistant",
      content: textParts.join("\n").trim(),
      token_count: tokenCount,
    });

    if (Array.isArray(content)) {
      let callOrd = 0;
      for (const c of content) {
        const cobj = asObj(c);
        if (!cobj || cobj.type !== "tool_use") continue;
        const tname = (cobj.name as string | undefined) ?? "?";
        const tid = cobj.id as string | undefined;
        const input = (asObj(cobj.input) ?? {}) as Record<string, unknown>;
        const isErr = tid ? errorIds.has(tid) : false;
        out.tool_calls.push({
          turn_ord: turnOrd,
          call_ord: callOrd,
          tool_name: tname,
          input,
          is_error: isErr,
        });
        if (tname === "Edit" || tname === "Write" || tname === "MultiEdit") {
          const fp = input.file_path as string | undefined;
          if (fp) {
            const editType: Edit["edit_type"] =
              tname === "Edit" ? "edit" :
              tname === "Write" ? "create" : "multi";
            out.edits.push({
              turn_ord: turnOrd,
              call_ord: callOrd,
              file_path: fp,
              edit_type: editType,
            });
          }
        }
        callOrd += 1;
      }
    }

    turnOrd += 1;
  }

  return out;
}
