# agentic-software-factory

Coding agents on a dedicated VPS: task → plan → implementation → tests → review → PR. Merges are manual.

- [`harden.sh`](scripts/harden.sh): VPS hardening and system packages (Debian 13, run as root)
- [`setup-agent.sh`](scripts/setup-agent.sh): agent tools for the `factory` user (no sudo)
- [`audit.sh`](scripts/audit.sh): security audit of the VPS (read-only)
- [`docs/vps-setup.md`](docs/vps-setup.md): checklist of manual steps
- [`docs/design-decisions/hardening.md`](docs/design-decisions/hardening.md): hardening scope and known gaps
