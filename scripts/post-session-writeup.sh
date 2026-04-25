#!/usr/bin/env bash
# post-session-writeup.sh — deterministic structured writeup of a
# completed session, for researcher review.
#
# Inputs (all already exist on disk):
#   $1                                         — session id (sid)
#   ${state_dir}/session-<sid>.tsv             — intervention log
#   transcript_path event in TSV               — recorded by stop.sh
#   git diff against the session's HEAD        — best effort
#
# Output: ${state_dir}/sessions/<sid>.md
#
# Idempotent: skips if the writeup already exists.
#
# This script is invoked in the background from session-start.sh; it
# must not depend on stdin and must fail open (exit 0) on errors.

set -u
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"

sid="${1:-}"
if [[ -z "$sid" ]]; then
  echo "usage: $0 <session-id>" >&2
  exit 1
fi

writeup="$(eh_session_writeup_path "$sid")"
tsv="$(eh_session_file "$sid")"

[[ -f "$writeup" ]] && exit 0
[[ -f "$tsv" ]] || exit 0

# transcript_path was logged once by stop.sh when present; pull the most
# recent (in case of multiple Stop events).
transcript_path="$(awk -F'\t' '$2=="transcript_path"{p=$3} END{print p}' "$tsv")"

EH_SID="$sid" \
EH_TSV="$tsv" \
EH_TRANSCRIPT="${transcript_path:-}" \
EH_WRITEUP="$writeup" \
EH_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}" \
python3 - <<'PY' || exit 0
import json
import os
import subprocess
from collections import Counter
from datetime import datetime

sid = os.environ["EH_SID"]
tsv_path = os.environ["EH_TSV"]
transcript = os.environ.get("EH_TRANSCRIPT") or ""
out_path = os.environ["EH_WRITEUP"]
project_dir = os.environ["EH_PROJECT_DIR"]


def parse_ts(t):
    if not t:
        return None
    try:
        return datetime.fromisoformat(t.replace("Z", "+00:00"))
    except Exception:
        return None


def fmt_duration(start, end):
    if not (start and end):
        return ""
    secs = int((end - start).total_seconds())
    h, rem = divmod(secs, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}h{m}m{s}s"
    if m:
        return f"{m}m{s}s"
    return f"{s}s"


# --- TSV parse -----------------------------------------------------------

events = []
with open(tsv_path) as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("\t", 2)
        if len(parts) < 2:
            continue
        events.append({
            "ts": parts[0],
            "kind": parts[1],
            "detail": parts[2] if len(parts) >= 3 else "",
        })

if not events:
    with open(out_path, "w") as fh:
        fh.write(f"# Session {sid}\n\n_(no recorded events)_\n")
    raise SystemExit(0)

start_ts = events[0]["ts"]
end_ts = events[-1]["ts"]
duration = fmt_duration(parse_ts(start_ts), parse_ts(end_ts))

# --- transcript parse (best effort) -------------------------------------

turn_count = None
model = None
tool_calls = Counter()
files_edited = []
turns = []  # list of (datetime|None, role, raw_ts)

if transcript and os.path.isfile(transcript):
    try:
        with open(transcript) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except Exception:
                    continue
                if not isinstance(msg, dict):
                    continue
                m = msg.get("message")
                if not isinstance(m, dict):
                    m = msg
                role = m.get("role") or msg.get("type")
                if msg.get("type") == "assistant" and not model:
                    model = m.get("model") or msg.get("model") or ""
                content = m.get("content")
                if isinstance(content, list):
                    for c in content:
                        if not isinstance(c, dict):
                            continue
                        ctype = c.get("type")
                        if ctype == "tool_use":
                            name = c.get("name", "?")
                            tool_calls[name] += 1
                            inp = c.get("input") or {}
                            if name in ("Edit", "Write", "MultiEdit"):
                                fp = inp.get("file_path")
                                if fp:
                                    files_edited.append(fp)
                if role in ("user", "assistant"):
                    raw = msg.get("timestamp") or ""
                    turns.append((parse_ts(raw), role, raw))
        turn_count = len(turns)
    except Exception:
        pass


def next_turn_after(ts_str):
    s = parse_ts(ts_str)
    if s is None:
        return None
    for t, role, raw in turns:
        if t and t > s:
            return (raw or "?", role)
    return None


# --- git diff stats ------------------------------------------------------

def git_run(args, timeout=10):
    try:
        r = subprocess.run(
            ["git", "-C", project_dir] + args,
            capture_output=True, text=True, timeout=timeout,
        )
        return r.stdout if r.returncode == 0 else ""
    except Exception:
        return ""


diff_files = [l for l in git_run(["diff", "--name-only", "HEAD"]).splitlines() if l]
diff_stat = git_run(["diff", "--stat", "HEAD"]).strip()


def is_test_path(p):
    p = p.lower()
    indicators = (
        "/test/", "/tests/", "/__tests__/", "/spec/", "/specs/",
        "_test.", ".test.", ".spec.", "/testdata/", "/fixtures/",
    )
    return any(i in p for i in indicators) or p.startswith("test_")


# --- taxonomy -----------------------------------------------------------

RISK_KINDS = {
    "agentic_threat_detected", "goal_conflict_detected", "urgency_detected",
    "sycophancy_prime_detected", "claim_evaluation_detected",
    "failure_spiral_primed", "bash_hack_smell", "test_edit_guarded",
    "subagent_warning_emitted",
}

interventions = [e for e in events if e["kind"] in RISK_KINDS]
hack_smells = [e for e in events if e["kind"] == "bash_hack_smell"]
gate_clean = any(e["kind"] == "stop_gate_clean" for e in events)

# --- markdown emit ------------------------------------------------------

L = []
L.append(f"# Session {sid}")
L.append("")
L.append("## Header")
L.append("")
L.append(f"- **Session id:** `{sid}`")
L.append(f"- **Start:** {start_ts}")
L.append(f"- **End:** {end_ts}")
if duration:
    L.append(f"- **Duration:** {duration}")
if turn_count is not None:
    L.append(f"- **Turns (transcript):** {turn_count}")
if model:
    L.append(f"- **Model:** `{model}`")
L.append(f"- **TSV events:** {len(events)}")
L.append(f"- **Risk-marker interventions:** {len(interventions)}")
L.append(f"- **Stop gate clean:** {'yes' if gate_clean else 'no'}")
L.append(f"- **Transcript captured:** {'yes' if (transcript and os.path.isfile(transcript)) else 'no'}")
L.append("")

L.append("## Intervention timeline")
L.append("")
if interventions:
    L.append("| Time | Kind | Detail | Next turn |")
    L.append("|---|---|---|---|")
    for ev in interventions:
        nxt = next_turn_after(ev["ts"])
        nxt_s = f"{nxt[1]} @ {nxt[0]}" if nxt else "_n/a_"
        detail = (ev["detail"] or "").replace("|", "\\|")[:80]
        L.append(f"| {ev['ts']} | `{ev['kind']}` | {detail} | {nxt_s} |")
else:
    L.append("_(no risk-marker interventions fired)_")
L.append("")

L.append("## Tool-call summary")
L.append("")
if tool_calls:
    for name, n in sorted(tool_calls.items(), key=lambda x: -x[1]):
        L.append(f"- `{name}`: {n} call(s)")
else:
    L.append("_(no tool calls captured — transcript may have been unavailable)_")
L.append("")

if files_edited:
    L.append("**Files edited (from transcript):**")
    for fp in sorted(set(files_edited)):
        L.append(f"- `{fp}`")
    L.append("")

L.append("## Diff summary")
L.append("")
if diff_files:
    L.append("**Files changed (vs HEAD at writeup time):**")
    for fp in diff_files:
        marker = " _(test)_" if is_test_path(fp) else ""
        L.append(f"- `{fp}`{marker}")
    L.append("")
    if diff_stat:
        L.append("```")
        L.append(diff_stat)
        L.append("```")
        L.append("")
else:
    L.append("_(no diff against HEAD, or git not available)_")
L.append("")

L.append("## Bash hack-smell hits")
L.append("")
if hack_smells:
    for ev in hack_smells:
        L.append(f"- `{ev['ts']}`: `{ev['detail']}`")
else:
    L.append("_(none)_")
L.append("")

L.append("## Notes")
L.append("")
L.append("_(researcher annotation — qualitative observations go here)_")
L.append("")

with open(out_path, "w") as fh:
    fh.write("\n".join(L))
PY

exit 0
