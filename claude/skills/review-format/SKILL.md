---
name: review-format
description: Format and severity levels for review findings. Use when writing or triaging a review.
---
One section per finding:

```
### [Blocking|Required|Suggestion] <title>
`path:line` · <subtask id, if known>
What is wrong, why it matters, suggested fix (1–4 lines).
```

- **Blocking**: wrong behaviour, security hole, unmet spec criterion, broken or gutted tests.
- **Required**: real problem to fix before merge (missed edge case, maintainability, unclear API).
- **Suggestion**: nice to have.

Findings only, no praise or summary. Nothing found: `No findings.`
