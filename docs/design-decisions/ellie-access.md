# Ellie → factory VPS access

Ellie (agent in the `aibox` container on the home RPi) logs in to the VPS as `factory` over SSH, also through Herdr, without being able to read the private key.

## Decision

Public SSH (port 822) + a dedicated key held by an **ssh-agent on the RPi host**. Only the agent socket is mounted into the container: Ellie can sign logins, but cannot copy the key.

The VPS keys of `factory` live in `/etc/ssh/authorized_keys/factory` (root-owned, rebuilt by every `harden.sh` run from `debian`'s keys plus Ellie's line; manual edits are overwritten). Without that, one login would be enough to append an attacker key to `~factory/.ssh/authorized_keys` and keep access without the socket.

Ellie's key line, built from `keys/ellie-factory.pub` (option changes and key rotation apply on the next run; delete the file to revoke):

```
restrict,pty ssh-ed25519 AAAA... ellie
```

- `restrict`: no port/agent/X11 forwarding, no PTY, no `~/.ssh/rc`;
- `pty`: interactive Herdr panes and `ssh factory`.
- No port forwarding: Herdr reaches the remote API through `herdr remote-api-bridge` inside the SSH session. If `herdr machine add factory` still fails without it, add `port-forwarding` to `ELLIE_KEY_OPTS` (`permitopen` could narrow TCP, but Ellie has a full shell there anyway, so it would add little; unix sockets cannot be narrowed).
- `keys/ellie-factory.pub` must be a single bare `ssh-ed25519` line; `harden.sh` refuses anything else, because extra lines or options would grant extra keys.

No `from=`: the RPi has no static public IP.

## Rejected for now

- **VPS in the main tailnet** (`tag:factory`, no default allow-all rule, only RPi → VPS): closes the public port, but Tailscale SSH authenticates the RPi node, so every process and container on the RPi gets the same access; one ACL mistake exposes the home network. Revisit when the public port must go.
- **Separate tailnet for the factory** (userspace Tailscale in aibox): full isolation, but a second account and the node key inside the container. Too much at this scale.

## Residual risks

- While the socket is mounted, anything in aibox can log in as `factory`. `ssh-add -c` needs a GUI prompt, so it is not an option on a headless RPi. The real boundary is what `factory` can do: no sudo, no `docker` group, narrow tokens ([hardening](hardening.md)).
- The agent on the VPS can still change everything else `factory` owns (`~/.bashrc`, `~/factory`, user services): the VPS is disposable, rebuild it after a suspected compromise.
- The other direction: Ellie's logins run `factory`'s shell startup files, which a compromised agent can edit. All output Ellie reads from the VPS (SSH, Herdr panes) is untrusted input that may carry prompt injection aimed at the RPi.

## Setup

### RPi (home-lab repo)

`just aibox ssh-setup` (details in home-lab `docs/aibox.md`):
- generates `~/.ssh/ellie-factory` on the host (no passphrase, so it loads after a reboot; never mounted into aibox);
- `aibox-ssh-agent.service` (user unit): ssh-agent with that key, socket private in `/run/user/1000`;
- `aibox-ssh-proxy.socket` + `.service`: `systemd-socket-proxyd` in a dir mounted read-only into aibox as `SSH_AUTH_SOCK`. ssh-agent drops connections from other UIDs, and the container user `node` is a different host UID (rootless Podman), so a direct socket mount does not work. The dir (0700 + ACL for `node`'s host UID) limits who can connect;
- from `Host factory` in the RPi host's `~/.ssh/config`, generates the `factory` entry (port 822, user `factory`, `StrictHostKeyChecking yes`) and a pinned VPS host key, mounted read-only as `/etc/ssh/ssh_config.d/factory.conf` and `/etc/ssh/ssh_known_hosts`. The container's `~/.ssh` stays writable for Herdr; the agent can override these only in its own `~/.ssh`, which affects only its own connections.

### VPS

1. The public key is `keys/ellie-factory.pub`.
2. `git pull && sudo bash scripts/harden.sh` (adds the key with the options above).

### Test (in the container)

```bash
ssh factory true
ssh -A factory 'echo $SSH_AUTH_SOCK'   # empty: no agent forwarding
herdr machine add factory
```
