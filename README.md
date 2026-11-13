# agentic-software-factory

Coding agents on a dedicated VPS: task → plan → implementation → tests → review → PR. Merges are manual.

- [`harden.sh`](scripts/harden.sh): VPS hardening and system packages (Debian 13, run as root)
- [`setup-agent.sh`](scripts/setup-agent.sh): agent tools for the `factory` user (no sudo)
- [`audit.sh`](scripts/audit.sh): security audit of the VPS (read-only)
- [`start-task.sh`](scripts/start-task.sh): start or resume a task (worktree + coordinator session)
- [`claude/`](claude/): agent definitions, skills and shared conventions, linked into `~/.claude` by `setup-agent.sh`
- [`docs/vps-setup.md`](docs/vps-setup.md): checklist of manual steps
- [`docs/design-decisions/hardening.md`](docs/design-decisions/hardening.md): hardening scope and known gaps

## Task flow

Approved spec → `coordinator` → `planner` ⇄ `plan-reviewer` → `test-writer` → `implementer` ×N → `reviewer-correctness` ∥ `reviewer-security` ∥ `reviewer-design` → `triage` → fixes ⇄ review → PR. Review loops stop after 5 rounds; then the coordinator opens a draft PR stating the problem. Progress lives in `docs/tasks/<slug>/tasks.md` in the project repo.
