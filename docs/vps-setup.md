# Factory VPS: checklist

OVH VPS-1 (BHS), Debian 13. [`harden.sh`](../scripts/harden.sh) and [`setup-agent.sh`](../scripts/setup-agent.sh) do most of the work. This file lists the steps the scripts can't do, in order.

**Users:** `debian` (admin, sudo) and `factory` (agents, no sudo).
**Open to the internet:** only SSH on port 822 (`SSH_PORT` in `harden.sh`): key-only, rate-limited by ufw, fail2ban.
**Keys of `factory`:** `/etc/ssh/authorized_keys/factory` (root-owned, so agents can't add keys), rebuilt by every `harden.sh` run from `debian`'s keys plus `keys/ellie-factory.pub`. Manual edits there are overwritten: add or revoke keys in those sources, then run `harden.sh` again.

> **Rescue:** KVM console in the OVH panel (VPS → "KVM") or rescue mode. Find both before you start.

## 1. Before hardening

- [ ] OVH panel: add your public key under *Account → SSH keys* (needed for rebuilds).
- [ ] From the laptop: `ssh-copy-id debian@<IP>`, then check that `ssh debian@<IP>` logs in with the key.
      Without it `harden.sh` stops, because disabling passwords would lock you out.

## 2. Hardening

On the VPS as `debian` (`ssh -t debian@<IP>`). The image may not ship git, so install it first:

```bash
sudo apt-get -o DPkg::Lock::Timeout=300 update && sudo apt-get install -y git
git clone https://github.com/pawelqs/agentic-software-factory
cd agentic-software-factory
sudo bash scripts/harden.sh
```

SSH moves from port 22 to 822. The current session stays open; new connections need the new port.

- [ ] The script reaches "Hardening done"; `ss -tulpn` shows nothing public except sshd on 822.
- [ ] **Keep this session open.** In a new terminal: `ssh -p 822 debian@<IP>` works with the key.
- [ ] If it prints "Reboot required": `sudo reboot`, then run it again (it should pass without changes).

## 3. Agent tools

In the same session, from the clone. The script is copied because `factory` may not be able to read `/home/debian`:

```bash
sudo install -o factory -g factory -m 755 scripts/setup-agent.sh /home/factory/
sudo -iu factory bash setup-agent.sh
```

- [ ] No `MISSING` in the checks (except maybe `herdr`).

## 4. Laptop

- [ ] `~/.ssh/config` (`IdentitiesOnly` stops the client from offering every agent key; failed offers count towards fail2ban bans):
  ```
  Host factory factory-admin
      HostName <IP>
      Port 822
      IdentityFile ~/.ssh/<your key>
      IdentitiesOnly yes
  Host factory
      User factory
  Host factory-admin
      User debian
  ```
- [ ] `ssh factory-admin` and `ssh factory` work.
- [ ] Herdr (if installed): `herdr machine add factory`, then `herdr --remote factory`.

## 4a. Ellie (RPi)

Ellie logs in as `factory` through an ssh-agent on the RPi host, without access to the private key: [ellie-access.md](design-decisions/ellie-access.md).

- [ ] RPi (home-lab): `Host factory` in the host's `~/.ssh/config`, then `just aibox ssh-setup` (key, agent + socket proxy, ssh config for aibox) and `just aibox deploy`.
- [ ] Public key committed as `keys/ellie-factory.pub`, then `harden.sh` run again.
- [ ] In aibox: `ssh factory true` and `herdr machine add factory`.

## 5. Secrets (on the VPS as `factory`)

Both go to `~/.config/factory/env` (chmod 600, created by `setup-agent.sh`), which `~/.config/factory/shellrc` loads at the top of `.bashrc`.

- [ ] **Claude:** on the laptop `claude setup-token` → `CLAUDE_CODE_OAUTH_TOKEN=...` in `env`.
      The token lasts a year and only allows inference. If it leaks, revoke it and create a new one.
- [ ] **GitHub:** account `ellie-7894` → *Settings → Developer settings → Tokens (classic)*: new token "factory", scopes **`repo` + `workflow`**
      (`workflow` lets agents set up CI; no `delete_repo`, no `admin:*`), with an expiry date → `GH_TOKEN=...` in `env`.
      Fine-grained PATs don't work for a collaborator on someone else's personal repo, hence classic.
- [ ] Test: `ssh factory 'gh auth status && claude -p "say hi"'`.
- [ ] Commits are authored as `ellie-7894` (set by `setup-agent.sh`); push goes through `gh auth git-credential`.

## 6. Finally

- [ ] Snapshot in the OVH panel (only one is kept, ~1.30 PLN net/month).
- [ ] Idempotency test: `ssh -t factory-admin 'cd agentic-software-factory && git pull && sudo bash scripts/harden.sh'` and `ssh factory 'bash setup-agent.sh'` pass a second time without errors.

## 7. Running a task

`setup-agent.sh` clones this repo to `~/factory` and links `claude/` into `~/.claude` (update: `git -C ~/factory pull`).

- [ ] `ssh factory 'claude agents'` lists the factory agents.
- [ ] In a Herdr pane on the VPS: `start-task <owner/repo> <name> <spec.md>` (gets the next free number, e.g. `007-<name>`). Run `start-task <owner/repo> <name>` to resume (e.g. after a usage-limit reset).

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
