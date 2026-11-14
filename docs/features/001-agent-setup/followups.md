# Followups: 001-agent-setup

## From review round 1
- `start-task.sh`: `owner1/app` and `owner2/app` share `~/projects/app` (key clone/worktree paths on `owner-repo` or verify `origin`); settle on one name (`start-task` vs `start-task.sh`).
- `setup-agent.sh`: `die` (or check in step 5) when `~/.claude/agents` is a real directory; check `start-task` on PATH; update the header line with the factory-agents step.
- Prompt tampering: agents can edit `~/factory` (prompts, `start-task.sh`) persistently. Record in `hardening.md` Known gaps; cheap check: `start-task` warns when `git -C ~/factory status --porcelain` is non-empty.
- Public repos: `followups.md` and the PR body disclose unfixed security findings; consider keeping them out for public repos.
- Req. 10 trims: move the shared reviewer output line (path, "don't edit code", reply counts) into `review-format`; cut the focus items in `reviewer-design.md` and "not over-engineered" in `plan-reviewer.md` that repeat the design principles; drop "Don't commit" in `implementer.md` (covered by `claude/CLAUDE.md`); drop `files`/`depends on` from the tasks.md subtask template (plan.md holds them).
