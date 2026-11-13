# agent-setup

## Summary
Agent definitions (`claude/`), launcher (`scripts/start-task.sh`) and their install in `setup-agent.sh`. Bootstrapped by hand: Ellie (RPi) acts as coordinator, planner and implementer; reviews and triage run as subagents using the new prompts.

## Artefacts
- Spec: specs/agent-setup.md (approved 2026-11-13)
- Reviews: docs/tasks/agent-setup/reviews/
- Branch: agent-setup

## Status
- [x] Spec committed
- [x] Plan (inline below, no plan review: bootstrap)
- [ ] Acceptance tests — n/a (markdown + shell); checked by `bash -n` and `claude agents` on the VPS
- [ ] Subtasks
- [ ] Review — round 0/5
- [ ] PR ready for review

## Subtasks
### S1 Shared conventions and skills — files: claude/CLAUDE.md, claude/skills/
- [x] factory CLAUDE.md, review-format, design-principles
### S2 Agent definitions — files: claude/agents/
- [x] coordinator, planner, plan-reviewer, test-writer, implementer, 3 reviewers, triage
### S3 Launcher and install — files: scripts/, README.md, docs/vps-setup.md
- [ ] start-task.sh, setup-agent.sh step, docs

## Notes
- 2026-11-13: subagents run natively (Agent tool) inside the coordinator session; coordinator runs as `claude --agent coordinator`.
