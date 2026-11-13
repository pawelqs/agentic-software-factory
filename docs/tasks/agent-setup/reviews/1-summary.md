# Review round 1 — triage

## Fixes

### S1 Shared conventions and skills
- **[Required] Reviewers told to append to `followups.md`** (correctness, raised as Suggestion; violates req. 7 and three parallel reviewers race on the same file) — `claude/CLAUDE.md:7`: change to "Out-of-scope findings go to `docs/tasks/<slug>/followups.md` (append); reviewers put them in their review as Suggestions."

### S2 Agent definitions
- **[Required] `disallowedTools: Edit` is nominal** (correctness Blocking → Required, merged with design) — `planner.md`, `plan-reviewer.md`, `reviewer-*.md`, `triage.md`: set `disallowedTools: Agent`. Docs check: `disallowedTools` removes tools by name from the pool, and the sub-agents docs example lists `Write, Edit` separately, so `Edit` does not remove `Write` (the "Edit rules apply to all file-editing tools" rule is about permission path rules, not the tool pool). The flow does not break, but Write/Bash still reach code, so the line adds text without effect.
- **[Required] Hardcoded `origin/main` base** (correctness) — `reviewer-correctness.md:8`, `reviewer-design.md:8`, `reviewer-security.md:8`: use `git diff origin/HEAD...HEAD`.
- **[Required] Parallel implementers + per-subtask commit mixes subtasks** (correctness; merged with security's stray-files Suggestion) — `coordinator.md:12`: "Commit after each batch of parallel implementers has finished; check `git status` for stray files first."
- **[Required] Coordinator may stop to ask the user** (correctness) — `coordinator.md:6`: add "Never wait for user input: decide, note it in tasks.md, continue."

### S3 Launcher and install
- **[Required] "Task flow" splits the README link list** (correctness + design, duplicate) — `README.md:11-15`: move the `docs/vps-setup.md` and `hardening.md` bullets up into the list; "Task flow" last.

## Rejected
- Review-loop files never committed explicitly — with the batch commit (`git add -A`) they land in the next commit and the worktree persists across resumes; no extra text needed.
- Findings without a subtask have no destination — triage assigns them to the closest subtask (as done here); more prompt text not worth it (req. 10).
- Agents can rewrite their own prompts (security Required → Suggestion, to followups) — same-user persistence is an accepted gap of YOLO on a dedicated VPS (`hardening.md` Known gaps); prompt tampering is one more instance, not a merge blocker.
- `start-task.sh` owner/repo validation — input comes from the operator, not an attacker; the same-name clone collision is kept in followups.
- Coordinator commits stray secrets — merged into the batch-commit fix above.

Accepted Suggestions → `docs/tasks/agent-setup/followups.md`.
