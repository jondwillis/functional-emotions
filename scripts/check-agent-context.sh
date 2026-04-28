#!/usr/bin/env bash
# Verify CLAUDE.md @-imports AGENTS.md so the project's harness-agnostic
# agent context actually loads under Claude Code. Fails open: warns via
# systemMessage but never blocks.
#
# Wired in by .claude/settings.json as a PostToolUse hook on
# Edit/Write/MultiEdit; reads the JSON payload from stdin to find which
# file was touched, only acts if it was CLAUDE.md or AGENTS.md.

set -u

if command -v dd >/dev/null 2>&1; then
  payload="$(dd bs=1 count=$((1024*1024)) 2>/dev/null || true)"
else
  payload="$(cat || true)"
fi

file_path=""
if command -v python3 >/dev/null 2>&1; then
  file_path="$(EH_JSON="$payload" python3 - <<'PY' 2>/dev/null || true
import json, os
try:
    d = json.loads(os.environ.get("EH_JSON","") or "{}")
    print(((d.get("tool_input") or {}).get("file_path") or ""))
except Exception:
    pass
PY
)"
fi

case "$(basename "$file_path" 2>/dev/null)" in
  CLAUDE.md|AGENTS.md) ;;
  *) exit 0 ;;
esac

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
claude_md="${project_dir}/CLAUDE.md"
agents_md="${project_dir}/AGENTS.md"

[[ -f "$claude_md" && -f "$agents_md" ]] || exit 0

if grep -qE '^@AGENTS\.md([[:space:]]|$)' "$claude_md"; then
  exit 0
fi

msg="★ CLAUDE.md is missing the \`@AGENTS.md\` import line — without it, AGENTS.md content won't load in Claude Code sessions. Add \`@AGENTS.md\` near the top of CLAUDE.md."
if command -v python3 >/dev/null 2>&1; then
  EH_MSG="$msg" python3 - <<'PY' 2>/dev/null || true
import json, os
print(json.dumps({"systemMessage": os.environ.get("EH_MSG","")}))
PY
else
  printf '%s\n' "$msg" >&2
fi

exit 0
