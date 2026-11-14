# Factory conventions

- Everything in repos is in English.
- Task `<slug>` = `<n>-<name>`, e.g. `001-login-page`.
- Kept in the repo, in `docs/features/<slug>/`: `spec.md`, `tasks.md`, `followups.md`.
- Temporary files (plans, reviews) go to `.agents/<slug>/`; it is git-ignored and never committed.
- Use `.agents/<slug>/` freely to talk to other agents: notes, questions, warnings, handoffs. Ideas to improve the process (prompts, workflow, tools) go to `.agents/<slug>/process.md` (append).
- Project docs: `docs/vision.md`, `docs/design-principles.md`, `docs/code-style.md`, `docs/design-decisions/`. Missing design principles or code style: use the factory default in `~/factory/docs/`.
- Reply with a short status and file paths. Details go to files.
- Only the coordinator edits `tasks.md` and commits. Commits follow Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`).
- Out-of-scope findings (bugs, friction, ideas) go to `docs/features/<slug>/followups.md` (append); reviewers put them in their review as Suggestions.
