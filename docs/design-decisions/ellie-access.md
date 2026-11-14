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

### RPi host (not in the container)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/ellie-factory -C ellie@rpi   # passphrase optional, see below
loginctl enable-linger "$USER"                                 # /run/user/$UID survives logout
```

`~/.config/systemd/user/ellie-agent.service`:

```ini
[Unit]
Description=ssh-agent for Ellie (factory VPS)

[Service]
Type=simple
Environment=SSH_AUTH_SOCK=%t/ellie-agent.sock
ExecStartPre=/bin/rm -f %t/ellie-agent.sock
ExecStart=/usr/bin/ssh-agent -D -a %t/ellie-agent.sock
ExecStartPost=/bin/sh -c 'sleep 1; ssh-add %h/.ssh/ellie-factory'

[Install]
WantedBy=default.target
```

`systemctl --user enable --now ellie-agent`, then `SSH_AUTH_SOCK=/run/user/$UID/ellie-agent.sock ssh-add -l` shows one key. With a passphrase, `ExecStartPost` fails and the key has to be added by hand after every reboot; without one, the key file on the host is the only copy to protect.

### aibox container

- `openssh-client` in the image.
- Compose: mount `/run/user/<uid>/ellie-agent.sock:/home/node/.ssh-agent.sock` and set `SSH_AUTH_SOCK=/home/node/.ssh-agent.sock`.
- The socket is `0600` for the host user. In rootless Podman the container user `node` maps to a subuid, not the host UID, so it gets `Permission denied`: use `userns_mode: keep-id` (check the other mounts after the switch).
- `~/.ssh/config` in the container (no `IdentityFile`; the agent holds exactly one key):
  ```
  Host factory
      HostName <VPS IP>
      Port 822
      User factory
  ```

### VPS

1. Commit the public key as `keys/ellie-factory.pub`.
2. `git pull && sudo bash scripts/harden.sh` (adds the key with the options above).

### Test (in the container)

```bash
ssh factory true
ssh -A factory 'echo $SSH_AUTH_SOCK'   # empty: no agent forwarding
herdr machine add factory
```
