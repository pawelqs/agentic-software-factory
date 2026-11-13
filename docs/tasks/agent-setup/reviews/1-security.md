### [Required] Agents can rewrite their own prompts and launcher persistently
`scripts/setup-agent.sh:71-86`
`~/.claude/{agents,skills,CLAUDE.md}` and `~/.local/bin/start-task` are symlinks into `~/factory`, a clone owned and writable by `factory`. Any YOLO agent, or a prompt injection from a project repo or a dependency, can edit e.g. `~/factory/claude/agents/reviewer-security.md` or `start-task.sh`. The change survives across tasks and repos, and `git pull --ff-only` keeps uncommitted edits to files it does not touch. Unlike `~/.bashrc` tampering, a weakened reviewer prompt quietly removes a review gate and the human never sees it in a PR. Cheap fix: have `setup-agent.sh` warn on `git -C ~/factory status --porcelain` output (or `git reset --hard origin/main`). Better: keep the clone owned by `debian` and read-only for `factory`.

### [Suggestion] `start-task.sh` does not validate `owner/repo`
`scripts/start-task.sh:10-16`
`repo` goes unchecked into paths (`${repo#*/}`) and into `gh repo clone`. A value like `x/../../foo` escapes `~/projects`, and one starting with `-` is parsed as an option. Repos with the same name under two owners share `~/projects/<name>`, so a task can silently run against, and push to, the wrong origin, which could leak private code into another repo. Fix: check `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$` and confirm that `git -C "$clone" remote get-url origin` matches `$repo`. Or key the clone path on `owner-repo`.

### [Suggestion] Unresolved security findings are published in committed files and the PR body
`claude/agents/coordinator.md:16` · `claude/agents/triage.md:13`
Review files under `docs/tasks/<slug>/reviews/`, `followups.md` and the PR body ("rejected and unresolved findings") describe vulnerabilities that were not fixed. On a public project repo this discloses them before they are fixed. Fix: for public repos, leave unresolved security findings out of commits and the PR body (or keep `reviews/` out of git) and report them privately.

### [Suggestion] Token-scope docs contradict the deployed setup
`docs/design-decisions/hardening.md:14` · `docs/vps-setup.md:67` · `scripts/setup-agent.sh:59`
These files list "`repo` scope only (no `workflow`)" as a mitigation, but the bot token has `repo`+`workflow`. With `workflow`, an injected agent can push `.github/workflows/*` to a task branch, and on `push`/`pull_request` those workflows run with the repo's Actions secrets. Branch protection on `main` does not stop that. Fix: update the docs and record this as an accepted risk, or drop `workflow`. Also, an agent reviewer is not a control here: only human review of `.github/` changes is.

### [Suggestion] Coordinator commits may include stray secrets or untracked files
`claude/agents/coordinator.md:9-13`
The coordinator commits after each step without guidance on what to stage. All agents inherit `GH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN` and can write files such as `.env` or debug logs, so `git add -A` could push them. Fix: tell the coordinator to stage only files that subagents report, and to check `git status` for untracked files before committing.
