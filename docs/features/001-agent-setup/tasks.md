# 001-agent-setup

## Summary
Agent definitions (`claude/`), launcher (`scripts/start-task.sh`) and their install in `setup-agent.sh`. Bootstrapped by hand: Ellie (RPi) acts as coordinator, planner and implementer; reviews and triage run as subagents using the new prompts.

## Artefacts
- Spec: spec.md (approved 2026-11-13, req. 12 added 2026-11-14) · Followups: followups.md
- Reviews: not committed (round 1 summary is in the PR description)
- Branch: agent-setup · PR: #4

## Status
- [x] Spec committed
- [x] Plan (inline below, no plan review: bootstrap)
- [x] Acceptance tests — n/a (markdown + shell); start-task.sh tested locally with a fake `claude`; `claude agents` to check on the VPS
- [x] Subtasks
- [x] Review — round 1/5: 0 Blocking, 6 Required accepted and fixed; round 2 skipped, fixes were mechanical and checked by the coordinator
- [x] S4 docs layout (req. 12)
- [x] PR ready for review

## Subtasks
### S1 Shared conventions and skills — files: claude/CLAUDE.md, claude/skills/
- [x] factory CLAUDE.md, review-format
### S2 Agent definitions — files: claude/agents/
- [x] coordinator, planner, plan-reviewer, test-writer, implementer, 3 reviewers, triage
### S3 Launcher and install — files: scripts/, README.md, docs/vps-setup.md
- [x] start-task.sh, setup-agent.sh step, docs
### S4 Docs layout — files: claude/, docs/, scripts/start-task.sh
- [x] `docs/features/<n>-<name>/`, design principles and code style as docs with factory defaults, temporary files in `.agents/`
- [x] start-task.sh: numbering, resume by name, remote-only branch, `.agents/` in `info/exclude`

## Notes
- 2026-11-13: subagents run natively (Agent tool) inside the coordinator session; coordinator runs as `claude --agent coordinator`.
- 2026-11-13: accepted suggestions from review round 1 are in followups.md (not done in this PR).
- 2026-11-14: design principles and code style: project file first, else `~/factory/docs/`. Task number: next free on origin/HEAD and task branches, zero-padded to 3 digits.
