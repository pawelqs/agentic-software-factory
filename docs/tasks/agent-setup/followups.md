# Followups: agent-setup

## From review round 1
- `start-task.sh`: check the spec path exists before creating the worktree; `git worktree prune` first; handle a `task/<slug>` branch that exists only on origin; `owner1/app` and `owner2/app` share `~/projects/app` (key clone/worktree paths on `owner-repo` or verify `origin`).
- `start-task.sh`: add a `die()` helper like the other scripts, inline usage string instead of `sed -n '4,6p' "$0"`; settle on one name (`start-task` vs `start-task.sh`).
- `setup-agent.sh`: `die` (or check in step 5) when `~/.claude/agents` is a real directory; check `start-task` on PATH; update the header line with the factory-agents step.
- Prompt tampering: agents can edit `~/factory` (prompts, `start-task.sh`) persistently. Record in `hardening.md` Known gaps; cheap check: `start-task` warns when `git -C ~/factory status --porcelain` is non-empty.
- Token docs: `hardening.md:14`, `vps-setup.md:68`, `setup-agent.sh:59` say `repo` only, but the token has `repo`+`workflow`. Update and record as accepted risk (task branches can run modified workflows with Actions secrets; only human review of `.github/` changes guards this).
- Public repos: review files, `followups.md` and the PR body disclose unfixed security findings; consider keeping them out for public repos.
- Req. 10 trims: move the shared reviewer output line (path, "don't edit code", reply counts) into `review-format`; cut the focus items in `reviewer-design.md` and "not over-engineered" in `plan-reviewer.md` that repeat `design-principles`; drop "Don't commit" in `implementer.md` (covered by `claude/CLAUDE.md`); drop `files`/`depends on` from the tasks.md subtask template (plan.md holds them).
