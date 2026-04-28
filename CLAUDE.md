@AGENTS.md

## Claude Code specifics

- This repo *is* a Claude Code plugin. When iterating on a hook or
  skill, prefer testing in a separate scratch project rather than the
  plugin source dir, so the in-development hook scripts don't fire on
  the meta-development session and create confusing loops.
- There is no test/lint/build step. The "is it correct?" loop is:
  edit a script, install the plugin in a scratch project, run a
  scenario from `docs/SCENARIOS.md`, inspect
  `.claude/.functional-emotions/session-*.tsv` and
  `/functional-emotions:diagnose`.
- Skill auto-invocation triggers depend on the description text in
  each `skills/*/SKILL.md` frontmatter. When two skills overlap, sharpen
  the descriptions rather than merging — the bodies are usually doing
  different work even when the triggers look similar.
- The reviewer subagent has persistent memory under
  `.claude/agents/reviewer/`; consult it via `/functional-emotions:review`.
