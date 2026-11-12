# Factory VPS: checklist

OVH VPS-1 (BHS), Debian 13. [`harden.sh`](../harden.sh) and [`setup-agent.sh`](../setup-agent.sh) do most of the work. This file lists the steps the scripts can't do, in order.

**Users:** `debian` (admin, sudo) and `factory` (agents, no sudo).
**Open to the internet:** only SSH (22/tcp): key-only, rate-limited by ufw, fail2ban.

> **Rescue:** KVM console in the OVH panel (VPS → "KVM") or rescue mode. Find both before you start.

## 1. Before hardening

- [ ] OVH panel: add your public key under *Account → SSH keys* (needed for rebuilds).
- [ ] From the laptop: `ssh-copy-id debian@<IP>`, then check that `ssh debian@<IP>` logs in with the key.
      Without it `harden.sh` stops, because disabling passwords would lock you out.

## 2. Hardening

```bash
scp harden.sh debian@<IP>:
ssh -t debian@<IP> 'sudo bash harden.sh'
```

- [ ] The script reaches "Hardening done"; `ss -tulpn` shows nothing public except sshd.
- [ ] **Keep this session open.** In a new terminal: `ssh debian@<IP>` still works with the key.
- [ ] If it prints "Reboot required": `sudo reboot`, then run it again (it should pass without changes).

## 3. Agent tools

```bash
scp setup-agent.sh factory@<IP>:
ssh factory@<IP> 'bash setup-agent.sh'
```

- [ ] No `MISSING` in the checks (except maybe `herdr`).

## 4. Laptop

- [ ] `~/.ssh/config` (`IdentitiesOnly` stops the client from offering every agent key; failed offers count towards fail2ban bans):
  ```
  Host factory factory-admin
      HostName <IP>
      IdentityFile ~/.ssh/<your key>
      IdentitiesOnly yes
  Host factory
      User factory
  Host factory-admin
      User debian
  ```
- [ ] Herdr (if installed): `herdr machine add factory`, then `herdr --remote factory`.

## 5. Secrets (on the VPS as `factory`)

Both go to `~/.config/factory/env` (chmod 600, created by `setup-agent.sh`), which `~/.config/factory/shellrc` loads at the top of `.bashrc`.

- [ ] **Claude:** on the laptop `claude setup-token` → `CLAUDE_CODE_OAUTH_TOKEN=...` in `env`.
      The token lasts a year and only allows inference. If it leaks, revoke it and create a new one.
- [ ] **GitHub:** account `ellie-7894` → *Settings → Developer settings → Tokens (classic)*: new token "factory", **`repo` scope only**
      (no `workflow`, no `delete_repo`), with an expiry date → `GH_TOKEN=...` in `env`.
      Fine-grained PATs don't work for a collaborator on someone else's personal repo, hence classic.
- [ ] Test: `ssh factory 'gh auth status && claude -p "say hi"'`.
- [ ] Commits are authored as `ellie-7894` (set by `setup-agent.sh`); push goes through `gh auth git-credential`.

## 6. Finally

- [ ] Snapshot in the OVH panel (only one is kept, ~1.30 PLN net/month).
- [ ] Idempotency test: `ssh -t factory-admin 'sudo bash harden.sh'` and `ssh factory 'bash setup-agent.sh'` pass a second time without errors.

## Open

- How Herdr should start after a reboot (`systemd --user` unit?). The docs don't describe a unit; `loginctl enable-linger factory` is already set.
- OVH API rebuild (`POST /vps/{id}/rebuild`) + scripts as a single step.

## Done

| Step | Date | Notes |
|---|---|---|
| Before hardening | | |
| Hardening | | |
| Agent tools | | |
| Laptop | | |
| Secrets | | |
| Snapshot | | |
