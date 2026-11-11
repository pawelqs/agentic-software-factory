#!/usr/bin/env bash
# Bootstrap + hardening of the factory VPS (OVH VPS-1, Debian 13).
#
# Usage (from the laptop):
#   scp bootstrap.sh debian@<IP>: && ssh -t debian@<IP> 'sudo bash bootstrap.sh'
#   # after SSH over Tailscale works:
#   ssh -t debian@factory 'sudo bash bootstrap.sh --lockdown'
#
# Idempotent: safe to run again. Manual steps: docs/vps-setup.md
set -euo pipefail

HOSTNAME_NEW="factory"
ADMIN_USER="debian"
AGENT_USER="factory"
TS_TAG="tag:factory"
SWAP_SIZE="4G"
GIT_NAME="ellie-7894"
GIT_EMAIL="355491988+ellie-7894@users.noreply.github.com"
LOCK_MARKER="/etc/factory/locked-down"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: sudo bash bootstrap.sh [--lockdown | --help]

  (no args)    install and harden everything (idempotent)
  --lockdown   close public SSH (port 22); only allowed from an SSH session over Tailscale

Optional env: TS_AUTHKEY=tskey-...  tagged auth key for 'tailscale up' (not stored anywhere)
EOF
}

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# Runs a script as the agent user with a clean login-like environment.
as_agent() {
  runuser -u "$AGENT_USER" -- env -i \
    HOME="/home/$AGENT_USER" USER="$AGENT_USER" LOGNAME="$AGENT_USER" SHELL=/bin/bash \
    PATH="/home/$AGENT_USER/.local/bin:/home/$AGENT_USER/.local/share/mise/shims:/usr/local/bin:/usr/bin:/bin" \
    bash -c "cd ~ && $1"
}

# True when some established SSH session comes from a Tailscale address.
# Checked with ss, because sudo strips SSH_CONNECTION.
ssh_session_over_tailscale() {
  local peer ip o2
  while read -r peer; do
    ip=${peer%:*}; ip=${ip#[}; ip=${ip%]}; ip=${ip#::ffff:}
    case "$ip" in
      fd7a:115c:a1e0:*) return 0 ;;
      100.*)
        o2=$(cut -d. -f2 <<<"$ip")
        if (( o2 >= 64 && o2 <= 127 )); then return 0; fi ;;
    esac
  done < <(ss -Htn state established '( sport = :22 )' | awk '{print $4}')
  return 1
}

lockdown() {
  log "Lockdown: closing public SSH"
  command -v tailscale >/dev/null || die "Tailscale is not installed. Run bootstrap first."
  [[ "$(tailscale status --json | jq -r .BackendState)" == "Running" ]] \
    || die "Tailscale is not running."
  ufw status | grep -q 'on tailscale0' || die "No ufw rule for SSH on tailscale0. Run bootstrap first."
  ssh_session_over_tailscale \
    || die "No SSH session over Tailscale. Connect with 'ssh -t ${ADMIN_USER}@${HOSTNAME_NEW}' and run --lockdown from there."

  install -d -m 755 /etc/factory
  touch "$LOCK_MARKER"
  ufw delete limit 22/tcp >/dev/null 2>&1 || true
  ufw delete allow 22/tcp >/dev/null 2>&1 || true
  systemctl disable --now fail2ban >/dev/null 2>&1 || true
  ufw status verbose
  log "Done. Check from the laptop that 'nc -vz -w5 <public IP> 22' times out."
  log "Rescue: KVM console in the OVH panel, then: sudo rm $LOCK_MARKER && sudo ufw limit 22/tcp"
}

preflight() {
  [[ $EUID -eq 0 ]] || die "Run as root: sudo bash bootstrap.sh"
  grep -q '^ID=debian' /etc/os-release || die "This script expects Debian."
  id "$ADMIN_USER" >/dev/null 2>&1 || die "User $ADMIN_USER does not exist."
  [[ -s "/home/$ADMIN_USER/.ssh/authorized_keys" ]] \
    || die "/home/$ADMIN_USER/.ssh/authorized_keys is empty. Run 'ssh-copy-id ${ADMIN_USER}@<IP>' first, otherwise disabling passwords locks you out."
}

step_base() {
  log "1/11 Hostname, upgrade, packages"
  hostnamectl set-hostname "$HOSTNAME_NEW"
  if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$HOSTNAME_NEW/" /etc/hosts
  else
    printf '127.0.1.1\t%s\n' "$HOSTNAME_NEW" >> /etc/hosts
  fi
  # Stop cloud-init from resetting the hostname on reboot.
  if [[ -d /etc/cloud/cloud.cfg.d ]]; then
    printf 'preserve_hostname: true\nmanage_etc_hosts: false\n' > /etc/cloud/cloud.cfg.d/99-factory.cfg
  fi

  apt-get update
  apt-get "${APT_OPTS[@]}" full-upgrade
  apt-get "${APT_OPTS[@]}" install \
    git tmux ufw fail2ban python3-systemd unattended-upgrades \
    build-essential ripgrep jq curl gnupg ca-certificates

  # gh from the official GitHub apt repo
  install -d -m 755 /etc/apt/keyrings
  if [[ ! -s /etc/apt/keyrings/githubcli-archive-keyring.gpg ]]; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
    chmod 644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
  fi
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get update
  apt-get "${APT_OPTS[@]}" install gh
}

step_unattended() {
  log "2/11 Unattended upgrades (Debian defaults: stable + security, no auto-reboot)"
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  systemctl enable --now unattended-upgrades >/dev/null
}

step_swap_journald() {
  log "3/11 Swap $SWAP_SIZE, swappiness, journald limit"
  if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
    [[ -f /swapfile ]] || fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
  fi
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo 'vm.swappiness=10' > /etc/sysctl.d/99-factory.conf
  sysctl -q -p /etc/sysctl.d/99-factory.conf

  install -d -m 755 /etc/systemd/journald.conf.d
  printf '[Journal]\nSystemMaxUse=500M\n' > /etc/systemd/journald.conf.d/size.conf
  systemctl restart systemd-journald
}

step_agent_user() {
  log "4/11 User $AGENT_USER (no sudo)"
  id "$AGENT_USER" >/dev/null 2>&1 || useradd -m -U -s /bin/bash "$AGENT_USER"
  if id -nG "$AGENT_USER" | tr ' ' '\n' | grep -qx sudo; then
    gpasswd -d "$AGENT_USER" sudo >/dev/null
  fi
  install -d -m 700 -o "$AGENT_USER" -g "$AGENT_USER" "/home/$AGENT_USER/.ssh"
  install -m 600 -o "$AGENT_USER" -g "$AGENT_USER" \
    "/home/$ADMIN_USER/.ssh/authorized_keys" "/home/$AGENT_USER/.ssh/authorized_keys"
  loginctl enable-linger "$AGENT_USER"
}

step_sshd() {
  log "5/11 SSH hardening"
  # 10-* is read before 50-cloud-init.conf; the first value wins in sshd.
  cat > /etc/ssh/sshd_config.d/10-hardening.conf <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers $ADMIN_USER $AGENT_USER
MaxAuthTries 3
X11Forwarding no
EOF
  sshd -t || die "sshd config test failed. Not reloading."
  systemctl reload ssh
}

step_fail2ban() {
  log "6/11 fail2ban"
  cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
backend = systemd
EOF
  if [[ -f "$LOCK_MARKER" ]]; then
    systemctl disable --now fail2ban >/dev/null 2>&1 || true
    echo "Locked down: fail2ban stays off (no public SSH)."
  else
    systemctl enable fail2ban >/dev/null
    systemctl restart fail2ban
  fi
}

step_ufw() {
  log "7/11 Firewall (ufw)"
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow in on tailscale0 to any port 22 proto tcp >/dev/null
  ufw allow 41641/udp comment 'tailscale direct' >/dev/null
  if [[ -f "$LOCK_MARKER" ]]; then
    ufw delete limit 22/tcp >/dev/null 2>&1 || true
  else
    ufw limit 22/tcp comment 'public ssh until --lockdown' >/dev/null
  fi
  ufw --force enable >/dev/null
  ufw status verbose
}

step_tailscale() {
  log "8/11 Tailscale"
  command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sh
  systemctl enable --now tailscaled >/dev/null
  if [[ "$(tailscale status --json 2>/dev/null | jq -r .BackendState)" == "Running" ]]; then
    echo "Already connected, skipping 'tailscale up'."
  else
    echo "Requires tagOwners for $TS_TAG in the tailnet policy (docs/vps-setup.md)."
    local args=(--hostname="$HOSTNAME_NEW" --advertise-tags="$TS_TAG")
    if [[ -n "${TS_AUTHKEY:-}" ]]; then args+=(--auth-key="$TS_AUTHKEY"); fi
    tailscale up "${args[@]}"
  fi
}

step_agent_tools() {
  log "9/11 Agent tools as $AGENT_USER: mise + node, Claude Code, uv, Herdr"
  as_agent '
    set -euo pipefail
    [[ -x ~/.local/bin/mise ]] || curl -fsSL https://mise.run | sh
    ~/.local/bin/mise use -g node@lts
    [[ -x ~/.local/bin/claude ]] || curl -fsSL https://claude.ai/install.sh | bash
    [[ -x ~/.local/bin/uv ]] || curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
  '
  # Herdr is not critical: a broken installer must not stop the bootstrap.
  if ! as_agent 'command -v herdr >/dev/null || curl -fsSL https://herdr.dev/install.sh | sh'; then
    warn "Herdr install failed. See https://herdr.dev/docs/install/ (tmux is installed as a fallback)."
  fi

  as_agent "
    set -euo pipefail
    git config --global --unset-all credential.https://github.com.helper || true
    git config --global --add credential.https://github.com.helper ''
    git config --global --add credential.https://github.com.helper '!gh auth git-credential'
    git config --global user.name '$GIT_NAME'
    git config --global user.email '$GIT_EMAIL'
    git config --global init.defaultBranch main
  "
}

step_shellrc() {
  log "10/11 Shell environment for $AGENT_USER"
  local home="/home/$AGENT_USER" cfg="/home/$AGENT_USER/.config/factory"
  install -d -m 700 -o "$AGENT_USER" -g "$AGENT_USER" "$home/.config" "$cfg"

  cat > "$cfg/shellrc" <<'EOF'
# Managed by bootstrap.sh. Sourced at the top of ~/.bashrc, so it also works for 'ssh factory cmd'.
for d in "$HOME/.local/share/mise/shims" "$HOME/.local/bin"; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
export PATH
if [ -r "$HOME/.config/factory/env" ]; then
  set -a; . "$HOME/.config/factory/env"; set +a
fi
EOF
  chown "$AGENT_USER:$AGENT_USER" "$cfg/shellrc"

  if [[ ! -f "$cfg/env" ]]; then
    cat > "$cfg/env" <<'EOF'
# Factory secrets. chmod 600, never commit. Exported by ~/.config/factory/shellrc.
# CLAUDE_CODE_OAUTH_TOKEN=   # from 'claude setup-token' (run on the laptop)
# GH_TOKEN=                  # classic PAT of ellie-7894 "factory", scope: repo only
EOF
  fi
  chown "$AGENT_USER:$AGENT_USER" "$cfg/env"
  chmod 600 "$cfg/env"

  local line='[ -r "$HOME/.config/factory/shellrc" ] && . "$HOME/.config/factory/shellrc"'
  touch "$home/.bashrc"
  if ! grep -qF '.config/factory/shellrc' "$home/.bashrc"; then
    { echo "$line"; cat "$home/.bashrc"; } > "$home/.bashrc.new"
    mv "$home/.bashrc.new" "$home/.bashrc"
  fi
  chown "$AGENT_USER:$AGENT_USER" "$home/.bashrc"
}

step_verify() {
  log "11/11 Checks"
  echo "--- $AGENT_USER tools (fresh login shell)"
  runuser -l "$AGENT_USER" -c '
    for c in node claude uv gh git tmux herdr; do
      printf "%-7s " "$c"
      if ! command -v "$c" >/dev/null; then echo MISSING; continue; fi
      if [ "$c" = tmux ]; then tmux -V; else "$c" --version 2>&1 | head -n1; fi
    done
    id
  '
  echo "--- sshd"
  sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin|allowusers|maxauthtries) '
  echo "--- tailscale"
  tailscale ip -4 2>/dev/null || warn "Tailscale has no IP yet."
  [[ -f /var/run/reboot-required ]] && warn "Reboot required (kernel/libc update): sudo reboot"

  if [[ -f "$LOCK_MARKER" ]]; then
    log "Bootstrap done. Public SSH stays closed."
  else
    log "Bootstrap done. Next: test 'ssh ${ADMIN_USER}@${HOSTNAME_NEW}' over Tailscale, then run --lockdown from there."
  fi
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --lockdown) [[ $EUID -eq 0 ]] || die "Run as root."; lockdown; exit 0 ;;
    "") ;;
    *) usage; exit 1 ;;
  esac
  preflight
  step_base
  step_unattended
  step_swap_journald
  step_agent_user
  step_sshd
  step_fail2ban
  step_ufw
  step_tailscale
  step_agent_tools
  step_shellrc
  step_verify
}

main "$@"
