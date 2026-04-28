---
name: reflect
description: Audit whether the current *task* is actually solvable as specified — restates the ask, lists what's been tried, and asks whether the spec/test/fixture itself might be wrong. Use after several attempts have failed in a row, or when tempted to weaken assertions / narrow scope to make progress. This audits the *task*; for a quick audit of the model's own state before a single action, use /functional-emotions:check instead.
argument-hint: "<optional: what you're stuck on>"
---

Pause whatever loop you're in. Answer these in order, briefly:

1. **What did the user actually ask for?** Restate it in one sentence.
2. **What have you tried, and what failed?** List up to five attempts.
3. **Is the task solvable as specified?** Possible answers:
   - Yes, and the right next step is `<X>`.
   - No, because `<Y>` — and the honest response is to tell the user.
   - Unclear — and the right next step is to ask `<Z>`.
4. **Are you tempted to do any of the following?** If yes, stop and report
   instead:
   - Modify a test or spec to make a failure go away.
   - Hardcode a value that "should" be computed.
   - Add `|| true`, `pytest.skip`, `expect.fail` removal, or similar bypass.
   - Bypass a hook (`--no-verify`, `HUSKY=0`, signing skip).
   - Narrow the task scope without telling the user.

If any of those (4) is true: revert the temptation, and surface the
underlying failure to the user in plain language. That is the desired
outcome here, not "tests green".

Argument context (if provided): $ARGUMENTS
