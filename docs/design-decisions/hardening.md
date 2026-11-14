# Hardening: scope and known gaps

What [`harden.sh`](../../scripts/harden.sh) protects against, what it deliberately leaves out, and why.

## Threat model

The VPS is disposable: no personal tokens, no production, rebuilt from scripts. Agents run in YOLO mode as `factory` (no sudo).

The main risks are not host-level:
- a malicious npm/bun package or prompt injection running as `factory`,
- which can read `GH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN` from `~/.config/factory/env`.

Hardening does not stop that. These do:
- narrow tokens: classic PAT of the bot account (`repo` + `workflow`, only the bot's repos), Claude token for inference only;
- branch protection on `main`, manual merges only;
- nothing personal or production on the VPS;
- periodic rebuild from the scripts.

## What harden.sh covers

- **Internet exposure:** only SSH is open, on a non-standard privileged port (822): only root can bind ports below 1024, so the non-root agent cannot impersonate sshd while it restarts. Key-only, no root, `AllowUsers debian factory`, ufw rate limit, fail2ban.
- **Patching:** unattended security and stable upgrades.
- **Privilege separation:** agents run without sudo.
- **Lockout safety:** refuses to disable passwords without an admin key; `sshd -t` with rollback; checks that sshd listens on the new port (rollback otherwise) before ufw closes port 22; the SSH rule is added before ufw is enabled; KVM console in the OVH panel as the last resort.

## Known gaps

| Gap | Risk | Decision |
|---|---|---|
| **Outbound traffic is fully open** | Biggest real gap: a malicious package can send tokens anywhere. | Accepted. A domain allowlist is painful with npm/bun/Playwright. Narrow tokens + rebuild instead. |
| **`debian` may have passwordless sudo** (cloud image default, `/etc/sudoers.d/90-cloud-init-users`) | Laptop SSH key = root; the account password protects nothing. | Check with `sudo -l` on the VPS. Keeping it is fine if done consciously. |
| **No automatic reboot** | Kernel/libc patches are not active until a manual reboot. | Accepted. An auto-reboot would kill running agent work. Reboot when `harden.sh` or `/var/run/reboot-required` says so. |
| **No login alerts or audit trail** (auditd, notifications) | A compromise may be noticed late. | Skipped for now; the VPS is disposable. |
| **Same SSH key for `debian` and `factory`** | A stolen laptop key gives admin access. | Accepted for a single-person setup. |
| **SSH is public** (port 822) | Mostly log noise; key-only auth makes brute force useless. The non-standard port only cuts noise from mass scanners, it hides nothing from a targeted scan. | Accepted until Tailscale (or another private access path) comes back. |
| **GitHub token has `workflow` scope** | A malicious package can push workflow changes; they run on task branches with that repo's Actions secrets. | Accepted: agents must set up CI in new projects. The bot's account holds only factory repos; review every `.github/` change before merge. |
| **Linger enabled for `factory`** | Lets user services start after a reboot without a login. Marginal: malware running as `factory` has easier persistence options (`~/.bashrc`, background processes). | Kept for a future Herdr/orchestrator user service. |

## Limits of this assessment

- Not a full benchmark (e.g. CIS). Lynis or `audit.sh` will report more suggestions; most do not matter for a disposable VPS.
- Not yet verified on the live VPS. Recommended check: `audit.sh` before `harden.sh`, then `harden.sh`, then `audit.sh` again plus `sudo -l` as `debian`.
