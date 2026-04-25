---
name: self-evaluate
description: Self-critical evaluation guard for test/spec files. Auto-loads when working on test files. Reminds you that modifying a failing test to make it pass is the canonical reward-hacking pattern, and asks you to declare the category of any test edit before saving.
paths: "**/*test*,**/*spec*,**/__tests__/**,**/tests/**,**/spec/**,**/specs/**"
---

You are working on a file that looks like a test, spec, or fixture.
Before editing or saving any change to this file, take a moment.

The Anthropic emotion-concepts research identifies one specific pattern
as the canonical reward-hack signature: **making a failing test pass by
weakening or deleting the assertion**. The desperate vector activates
hardest right before that decision.

Legitimate reasons to edit a test file exist:
  - Refactor (renames, deduplication, fixture rotation)
  - New behavior is being added under test, requiring new assertions
  - The test was wrong — captured the wrong intent or used a stale fixture

Before you save, name which category your edit is in. If it doesn't fit
any of those three, the edit is probably the failure mode. Revert it and
report the underlying failure to the user instead.

Default to the protective stance the paper identifies: *"Maybe the test
itself has an issue."* — that framing is anti-correlated with reward
hacking. Apply it here.
