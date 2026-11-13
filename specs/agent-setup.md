# Agent setup

Approved in chat, 2026-11-13.

## Goal
Agent definitions and a launcher that run one task from an approved spec to a PR, unattended, on the factory VPS.

## Requirements
1. Roles: coordinator, planner, plan-reviewer, test-writer, implementer, reviewer-correctness, reviewer-security, reviewer-design, triage.
2. Models: opus for coordinator, planning, reviews and triage; sonnet for tests and implementation. No haiku.
3. Spec is approved before the coordinator starts. The plan is for agents and needs no human approval.
4. Test-writer writes acceptance tests before implementation, in a separate, marked commit.
5. Implementers may change tests; reviewer-correctness checks that test changes make sense (nothing skipped, deleted or weakened without reason).
6. Several implementers per task, one subtask each, in one worktree per task.
7. Reviewers only write review files. Triage accepts or rejects each finding; accepted ones go back to implementers.
8. Loop limit: 5 rounds for plan review and for code review. Over the limit: draft PR describing the problem.
9. `tasks.md` in the project repo is the source of truth; a fresh coordinator can resume from it alone.
10. Prompts and definitions are as short as possible.
11. Works for many project repos; setup is reproducible from `setup-agent.sh`.

## Acceptance criteria
- `claude agents` on the VPS lists all roles from requirement 1.
- `start-task.sh <owner/repo> <slug> <spec.md>` creates the worktree and starts the coordinator; running it again without a spec resumes the task.
- Re-running `setup-agent.sh` is idempotent.

## Out of scope
Orchestrator, analyst (RPi side), Telegram notifications, new-repo template.
