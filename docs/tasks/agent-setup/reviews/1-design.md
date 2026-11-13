### [Required] New "Task flow" section splits the README link list
`README.md:11-15` · S3
The heading and paragraph were inserted mid-list, so the `docs/vps-setup.md` and `docs/design-decisions/hardening.md` bullets now sit under "Task flow" right after the paragraph. Move those two bullets up into the list above (after `claude/`) and keep "Task flow" as the last section.

### [Required] `disallowedTools: Edit` restricts nothing and gets in the way of agents that update files
`claude/agents/planner.md:5`, `plan-reviewer.md:5`, `reviewer-*.md:5`, `triage.md:5` · S2
Write and Bash are still allowed, so these agents can change any file anyway. Read-only behavior comes from the prompt alone. Meanwhile the flag gets in the way of work they're expected to do. From round 2 the planner revises `plan.md` and has to rewrite the whole file. Triage and reviewers append to `followups.md` (shared `CLAUDE.md`, `triage.md:13`) through read-modify-write with Write, and three reviewers run in parallel, so one can overwrite another's entries. Drop `Edit` from `disallowedTools` and keep only `Agent`, or make `followups.md` coordinator-only (reviewers put out-of-scope notes in their review file, and triage alone appends).

### [Suggestion] The same reviewer boilerplate appears in four prompts
`claude/agents/reviewer-correctness.md:12`, `reviewer-security.md:10`, `reviewer-design.md:10`, `plan-reviewer.md:10` · S1/S2
"Write `docs/tasks/<slug>/reviews/<n>-<kind>.md` in review-format. Don't edit code. Reply: counts per severity." repeats in each one. Every reviewer already loads `review-format`, so move the output path pattern, the "don't edit" rule and the reply format into that skill. The prompts then only carry input and focus (requirement 10).

### [Suggestion] reviewer-design's focus list repeats design-principles
`claude/agents/reviewer-design.md:8` · S2
"module depth and interfaces, leaked internals, needless layers or abstractions, duplication, naming" restates the preloaded `design-principles` skill. Keeping only what the skill lacks ("drift from the plan, consistency with the codebase and `styleguide.md`") would shorten it. Likewise "not over-engineered" in `plan-reviewer.md:8` repeats YAGNI.

### [Suggestion] "Don't commit" repeats the shared convention
`claude/agents/implementer.md:15` · S2
`claude/CLAUDE.md` already says only the coordinator commits. Drop it here, or else state it for test-writer too. Right now test-writer has no such line.

### [Suggestion] The tasks.md template copies plan.md content
`claude/agents/coordinator.md:46` · S2
`### S1 <name> — files: <paths> · depends on: —` copies the subtask files and dependencies from `plan.md`, and the two copies can drift once the plan is revised. Keep only the subtask id, name and status checkboxes in `tasks.md`; the plan holds the structure.

### [Suggestion] start-task.sh doesn't follow the other scripts' conventions
`scripts/start-task.sh:9,11,22` · S3
`harden.sh` and `setup-agent.sh` use `log`/`warn`/`die` helpers. This script uses raw `echo >&2` with mixed exit codes, and it prints usage with `sed -n '4,6p' "$0"`, which silently breaks if the header comment changes. Add a `die()` like the other scripts and an inline usage string. The usage also says `start-task.sh` while the installed command and the docs use `start-task` (`setup-agent.sh:86`, `docs/vps-setup.md:83`). Pick one name.

### [Suggestion] setup-agent.sh header doesn't mention the new step
`scripts/setup-agent.sh:2` · S3
The summary line still reads "bun, Claude Code, uv, Herdr, git config, shell env". Add "factory agents (~/factory → ~/.claude)" so the header matches the 5 steps.
