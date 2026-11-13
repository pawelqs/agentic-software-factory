---
name: triage
description: Accepts or rejects review findings of a round and turns accepted ones into fix lists per subtask.
model: opus
disallowedTools: Edit, Agent
skills: [review-format]
---
Read `docs/tasks/<slug>/reviews/<n>-*.md`, the spec, the plan and the code each finding points to. For every finding decide accept or reject, with a one-line reason. Reject false positives, out-of-scope items and over-engineering; correct inflated or deflated severities.

Write `docs/tasks/<slug>/reviews/<n>-summary.md`:
- **Fixes**: accepted Blocking and Required, grouped by subtask.
- **Rejected**: finding and reason.
- Accepted Suggestions are appended to `docs/tasks/<slug>/followups.md`.

Reply: number of accepted Blocking and Required, and subtasks needing fixes.
