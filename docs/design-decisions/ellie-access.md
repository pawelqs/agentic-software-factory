# Ellie → factory VPS access

Ellie (agent in the `aibox` container on the home RPi) logs in to the VPS as `factory` over SSH, also through Herdr, without being able to read the private key.

## Decision

Public SSH (port 822) + a dedicated key held by an **ssh-agent on the RPi host**. Only the agent socket is mounted into the container: Ellie can sign logins, but cannot copy the key.

The VPS keys of `factory` live in `/etc/ssh/authorized_keys/factory` (root-owned, `harden.sh`). Without that, one login would be enough to append an attacker key to `~factory/.ssh/authorized_keys` and keep access without the socket.

Ellie's key line (`harden.sh` adds it from `keys/ellie-factory.pub`):

```
restrict,port-forwarding,pty ssh-ed25519 AAAA... ellie@rpi
```

- `restrict`: no agent/X11 forwarding, no PTY, no `~/.ssh/rc`;
- `port-forwarding`: Herdr forwards its API over SSH (also enables unix-socket and `-R` forwarding; `authorized_keys` cannot narrow unix sockets);
- `pty`: interactive Herdr panes and `ssh factory`.

No `from=`: the RPi has no static public IP.

## Rejected for now

- **VPS in the main tailnet** (`tag:factory`, no default allow-all rule, only RPi → VPS): closes the public port, but Tailscale SSH authenticates the RPi node, so every process and container on the RPi gets the same access; one ACL mistake exposes the home network. Revisit when the public port must go.
- **Separate tailnet for the factory** (userspace Tailscale in aibox): full isolation, but a second account and the node key inside the container. Too much at this scale.

## Residual risks

- While the socket is mounted, anything in aibox can log in as `factory`. `ssh-add -c` needs a GUI prompt, so it is not an option on a headless RPi. The real boundary is what `factory` can do: no sudo, no `docker` group, narrow tokens ([hardening](hardening.md)).
- The agent on the VPS can still change everything else `factory` owns (`~/.bashrc`, `~/factory`, user services): the VPS is disposable, rebuild it after a suspected compromise.

## Setup

### RPi (home-lab repo)

`just aibox ssh-setup` (details in home-lab `docs/aibox.md`):
- generates `~/.ssh/ellie-factory` on the host (no passphrase, so it loads after a reboot; never mounted into aibox);
- `aibox-ssh-agent.service` (user unit): ssh-agent with that key, socket private in `/run/user/1000`;
- `aibox-ssh-proxy.socket` + `.service`: `systemd-socket-proxyd` in a dir mounted read-only into aibox as `SSH_AUTH_SOCK`. ssh-agent drops connections from other UIDs, and the container user `node` is a different host UID (rootless Podman), so a direct socket mount does not work. The dir (0700 + ACL for `node`'s host UID) limits who can connect;
- writes the container's `~/.ssh/config` (`Host factory`, port 822, user `factory`, no `IdentityFile`).

### VPS

1. The public key is `keys/ellie-factory.pub`.
2. `git pull && sudo bash scripts/harden.sh` (adds the key with the options above).

### Test (in the container)

```bash
ssh factory true
ssh -A factory 'echo $SSH_AUTH_SOCK'   # empty: no agent forwarding
herdr machine add factory
```
