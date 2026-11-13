### [Blocking] `disallowedTools: Edit` either blocks the agents' own output files or blocks nothing
`claude/agents/planner.md:5`, `plan-reviewer.md:5`, `reviewer-*.md:5`, `triage.md:5` · S2
In Claude Code permission matching, an `Edit` rule applies to all built-in file-editing tools, `Write` included. If that holds for `disallowedTools`, the planner cannot write `plan.md`, reviewers cannot write review files, and triage cannot write `<n>-summary.md` or append to `followups.md`, so the flow breaks at step 2. If it does not hold, `Write` and `Bash` still let them overwrite code, so the restriction does nothing. Fix: on the VPS, check whether a planner subagent can create `plan.md`. Then either drop `Edit` and rely on the prompt ("don't edit code"), or give an explicit `tools:` allowlist that includes `Write`.

### [Required] Reviewers diff against a hardcoded `origin/main`
`claude/agents/reviewer-correctness.md:8`, `reviewer-design.md:8`, `reviewer-security.md:8` · S2
`start-task.sh:29` branches from `origin/HEAD`, but all three reviewers run `git diff origin/main...HEAD`. On a repo whose default branch is not `main` (`master`, `develop`), the reviews fail or diff against the wrong base, which breaks requirement 11 ("many project repos"). Fix: use `origin/HEAD...HEAD` in the reviewers, or have the coordinator pass the base in the subagent prompt.

### [Required] Parallel implementers plus "commit after each subtask" can mix subtasks in one commit
`claude/agents/coordinator.md:12` · S2
All implementers share one worktree. When one finishes while another is still editing, a plain `git add -A && git commit` captures the other subtask's half-done changes. Fix: tell the coordinator to stage only the files the implementer reported (`git add <files>`), or to commit a parallel batch only once all of it has finished.

### [Required] Coordinator prompt never says to run unattended
`claude/agents/coordinator.md:6` · S2
The agent prompt replaces the default system prompt, and the session is interactive (`claude ... "<prompt>"`). Nothing stops the coordinator from ending its turn to ask the user a question or to confirm a step, and then the task stalls with nobody watching (spec Goal: "unattended"). Fix: add one line such as "Never wait for user input: decide, record it under Notes in tasks.md, continue. End your turn only after the PR (or draft PR) is open."

### [Required] README: "Task flow" section splits the file list
`README.md:11-15` · S3
The new section was inserted in the middle of the bullet list. The `docs/vps-setup.md` and `hardening.md` bullets now sit under "Task flow", directly after the paragraph. Fix: move lines 11–13 below the list.

### [Suggestion] Review-loop files are never committed explicitly
`claude/agents/coordinator.md:12-14` · S2
Nothing tells the coordinator to commit `plan.md`, `reviews/*.md` or `followups.md`. They end up in whichever later commit uses `git add -A`, or stay untracked and are lost if the worktree is removed. A fresh coordinator that resumes from a branch checkout then has no plan. Fix: commit `plan.md` after plan review and the review files together with each round's fixes.

### [Suggestion] Findings without a subtask have no destination
`claude/agents/triage.md:10-11`, `coordinator.md:14` · S2
Triage groups fixes "by subtask", and the coordinator spawns "one implementer per affected subtask". A cross-cutting finding with no subtask id (review-format: "if known") has no clear owner. Fix: let triage assign every accepted finding to an existing subtask or to a new `S<n+1> review fixes`.

### [Suggestion] Shared `followups.md` conflicts with requirement 7 and with parallel writes
`claude/CLAUDE.md:7` · S1
The shared conventions tell every agent, reviewers included, to append to `followups.md`. Requirement 7 says reviewers only write review files, and three reviewers running in parallel can overwrite each other's appends. Triage already moves accepted Suggestions there. Fix: restrict the line to non-reviewer agents (reviewers put out-of-scope items in their review as Suggestions).

### [Suggestion] start-task.sh edge cases
`scripts/start-task.sh:13-14,20-32` · S3
(a) A missing `spec.md` path is detected only by `install` after the worktree and branch already exist; check `[[ -z $spec || -f $spec ]]` up front. (b) If the worktree dir was deleted but is still registered, `worktree add` fails; run `git worktree prune` first. (c) If `task/<slug>` exists only on origin (e.g. after a draft PR and a re-clone), the script silently creates a fresh branch from `origin/HEAD` and the spec check fails; also check `refs/remotes/origin/task/$slug`. (d) `owner1/app` and `owner2/app` share `~/projects/app`.

### [Suggestion] setup-agent.sh: an unlinked `~/.claude/agents` only warns, and the checks don't cover the new step
`scripts/setup-agent.sh:80-81,88-96` · S3
If `~/.claude/agents` already exists as a real directory, the script only prints a warning, `claude agents` won't list the factory roles, and the run still looks successful. Consider `die`, or at least add a check in step 5: `start-task` on PATH and `readlink ~/.claude/agents`.
