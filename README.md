# agentic-software-factory

Coding agents on a dedicated VPS: task → plan → implementation → tests → review → PR. Merges are manual.

- [`harden.sh`](scripts/harden.sh): VPS hardening and system packages (Debian 13, run as root)
- [`setup-agent.sh`](scripts/setup-agent.sh): agent tools for the `factory` user (no sudo)
- [`audit.sh`](scripts/audit.sh): security audit of the VPS (read-only)
- [`start-task.sh`](scripts/start-task.sh): start or resume a task (worktree + coordinator session)
- [`claude/`](claude/): agent definitions, skills and shared conventions, linked into `~/.claude` by `setup-agent.sh`
- [`docs/vps-setup.md`](docs/vps-setup.md): checklist of manual steps
- [`docs/design-principles.md`](docs/design-principles.md), [`docs/code-style.md`](docs/code-style.md): factory defaults, used when a project has none
- [`docs/design-decisions/`](docs/design-decisions/): lasting decisions, e.g. [hardening](docs/design-decisions/hardening.md)
- [`docs/features/`](docs/features/): spec, tasks and followups per task

## Task flow

Approved spec → `coordinator` → `planner` ⇄ `plan-reviewer` → `test-writer` → `implementer` ×N → `reviewer-correctness` ∥ `reviewer-security` ∥ `reviewer-design` → `triage` → fixes ⇄ review → wrap-up (agent notes, process ideas, cleanup) → PR. Review loops stop after 5 rounds; then the coordinator opens a draft PR stating the problem. Each task is `<n>-<name>`. The project repo keeps `docs/features/<n>-<name>/{spec,tasks,followups}.md`; plans and reviews stay in the git-ignored `.agents/`.
