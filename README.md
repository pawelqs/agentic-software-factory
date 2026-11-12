# agentic-software-factory

Coding agents on a dedicated VPS: task → plan → implementation → tests → review → PR. Merges are manual.

- [`harden.sh`](harden.sh): VPS hardening and system packages (Debian 13, run as root)
- [`setup-agent.sh`](setup-agent.sh): agent tools for the `factory` user (no sudo)
- [`docs/vps-setup.md`](docs/vps-setup.md): checklist of manual steps
