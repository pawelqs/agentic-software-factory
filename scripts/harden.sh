#!/usr/bin/env bash
# Hardening of the factory VPS (OVH VPS-1, Debian 13). Based on the homelab RPi hardening script.
#
# Usage (on the VPS as the admin user, from a clone of this repo):
#   sudo bash scripts/harden.sh
# SSH then moves to port 822 (SSH_PORT); reconnect with ssh -p 822.
# Then install the agent tools as the agent user: setup-agent.sh
#
# Idempotent: safe to run again. Manual steps: docs/vps-setup.md
set -euo pipefail

HOSTNAME_NEW="factory"
ADMIN_USER="debian"
AGENT_USER="factory"
SWAP_SIZE="4G"
# Below 1024: only root can bind it, so a non-root agent cannot fake sshd while it is down.
SSH_PORT="822"
# Root-owned authorized_keys for the agent user, so a compromised agent cannot add its own keys.
KEYS_DIR="/etc/ssh/authorized_keys"
# Ellie's public key (optional); she signs logins via ssh-agent on the RPi: docs/design-decisions/ellie-access.md
ELLIE_KEY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/keys/ellie-factory.pub"
ELLIE_KEY_OPTS="restrict,port-forwarding,pty"

# Output helpers: step header, warning, fatal error.
log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# Refuses to run unless root on Debian and the admin user can log in with a key.
preflight() {
  [[ $EUID -eq 0 ]] || die "Run as root: sudo bash harden.sh"
  grep -q '^ID=debian' /etc/os-release || die "This script expects Debian."
  id "$ADMIN_USER" >/dev/null 2>&1 || die "User $ADMIN_USER does not exist."
  [[ -s "/home/$ADMIN_USER/.ssh/authorized_keys" ]] \
    || die "/home/$ADMIN_USER/.ssh/authorized_keys is empty. Run 'ssh-copy-id ${ADMIN_USER}@<IP>' first, otherwise disabling passwords locks you out."
}

# Sets the hostname, upgrades the system and installs packages (incl. gh).
step_base() {
  log "1/10 Hostname, upgrade, packages"
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

  apt-get -o DPkg::Lock::Timeout=300 update
  apt-get "${APT_OPTS[@]}" full-upgrade
  # The agent user has no sudo, so system packages it needs are installed here.
  apt-get "${APT_OPTS[@]}" install \
    ufw fail2ban python3-systemd nftables unattended-upgrades apparmor \
    git tmux build-essential ripgrep jq curl unzip ca-certificates

  # gh from the official GitHub apt repo
  install -d -m 755 /etc/apt/keyrings
  if [[ ! -s /etc/apt/keyrings/githubcli-archive-keyring.gpg ]]; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
    chmod 644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
  fi
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
  apt-get -o DPkg::Lock::Timeout=300 update
  apt-get "${APT_OPTS[@]}" install gh
}

# Enables daily automatic upgrades without auto-reboot.
step_unattended() {
  log "2/10 Unattended upgrades (Debian defaults: stable + security, no auto-reboot)"
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
  systemctl enable --now unattended-upgrades >/dev/null
}

# Creates the agent user without sudo and gives it root-owned SSH keys: admin keys + Ellie's restricted key.
step_agent_user() {
  log "3/10 User $AGENT_USER (no sudo)"
  id "$AGENT_USER" >/dev/null 2>&1 || useradd -m -U -s /bin/bash "$AGENT_USER"
  if id -nG "$AGENT_USER" | tr ' ' '\n' | grep -qx sudo; then
    gpasswd -d "$AGENT_USER" sudo >/dev/null
  fi
  install -d -m 700 -o "$AGENT_USER" -g "$AGENT_USER" "/home/$AGENT_USER/.ssh"

  # Seeded once from the admin keys, never from ~$AGENT_USER/.ssh: the agent could have written there.
  local keys="$KEYS_DIR/$AGENT_USER"
  install -d -m 755 -o root -g root "$KEYS_DIR"
  [[ -f $keys ]] || install -m 644 -o root -g root "/home/$ADMIN_USER/.ssh/authorized_keys" "$keys"
  if [[ -s $ELLIE_KEY ]]; then
    local key_blob
    read -r _ key_blob _ < "$ELLIE_KEY"
    grep -qF "$key_blob" "$keys" || echo "$ELLIE_KEY_OPTS $(<"$ELLIE_KEY")" >> "$keys"
  else
    warn "No $ELLIE_KEY; Ellie has no access to $AGENT_USER."
  fi
  loginctl enable-linger "$AGENT_USER"
}

# Key-only SSH on $SSH_PORT, no root, only the two users; rolls back if sshd can't use the config.
step_sshd() {
  log "4/10 SSH hardening (port $SSH_PORT)"
  # With socket activation the port comes from ssh.socket and Port below would be ignored.
  if systemctl is-active --quiet ssh.socket; then
    die "ssh.socket is active; this script expects ssh.service. Disable the socket first."
  fi
  # 10-* is read before 50-cloud-init.conf; the first value wins in sshd (Port is additive: no other Port line exists).
  local conf=/etc/ssh/sshd_config.d/10-hardening.conf
  cat > "$conf" <<EOF
Port $SSH_PORT
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers $ADMIN_USER $AGENT_USER
LoginGraceTime 20
AllowAgentForwarding no
X11Forwarding no

# The agent cannot edit this file. A Match block in an included file ends with that file.
Match User $AGENT_USER
    AuthorizedKeysFile $KEYS_DIR/%u
EOF
  if ! sshd -t; then
    rm -f "$conf"
    die "sshd config test failed. Removed $conf, not reloading."
  fi
  systemctl reload ssh

  # Open sessions survive the reload. Make sure new ones can connect before ufw closes port 22.
  local i
  for i in {1..10}; do
    if ss -Htln "sport = :$SSH_PORT" | grep -q .; then
      # sshd no longer reads it; removing it makes clear that the keys live in $KEYS_DIR.
      rm -f "/home/$AGENT_USER/.ssh/authorized_keys"
      return 0
    fi
    sleep 1
  done
  # sshd may have exited after a failed bind, so restart (open sessions survive it) instead of reload.
  rm -f "$conf"
  systemctl restart ssh || true
  die "sshd is not listening on port $SSH_PORT. Removed $conf and restarted ssh."
}

# Resets ufw, then denies all incoming traffic except rate-limited SSH on $SSH_PORT.
step_ufw() {
  log "5/10 Firewall (ufw)"
  # Start from a clean state so the rules below are the only ones (reset also disables ufw).
  ufw --force reset >/dev/null
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw limit "$SSH_PORT/tcp" comment 'ssh' >/dev/null
  ufw --force enable >/dev/null
}

# Bans IPs after repeated failed SSH logins.
step_fail2ban() {
  log "6/10 fail2ban"
  # The default jail bans on port 22 only.
  cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = $SSH_PORT
backend = systemd
maxretry = 3
findtime = 600
bantime = 3600
EOF
  systemctl enable fail2ban >/dev/null
  systemctl restart fail2ban
}

# Adds a swap file and caps the journal size (small disk).
step_swap_journald() {
  log "7/10 Swap $SWAP_SIZE, journald limit"
  if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
    [[ -f /swapfile ]] || fallocate -l "$SWAP_SIZE" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
  fi
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

  install -d -m 755 /etc/systemd/journald.conf.d
  printf '[Journal]\nSystemMaxUse=500M\n' > /etc/systemd/journald.conf.d/size.conf
  systemctl restart systemd-journald
}

# Network sysctl hardening, noexec /dev/shm, AppArmor check.
step_kernel() {
  log "8/10 Kernel and shared memory hardening"
  cat > /etc/sysctl.d/99-factory.conf <<'EOF'
vm.swappiness = 10
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.log_martians = 1
EOF
  sysctl -q --system

  # /dev/shm is the real tmpfs on Debian (/run/shm is a legacy symlink). Remount so no reboot is needed.
  if ! grep -qE '^\S+\s+/dev/shm\s' /etc/fstab; then
    echo 'tmpfs /dev/shm tmpfs defaults,nodev,nosuid,noexec 0 0' >> /etc/fstab
  fi
  mount -o remount,nodev,nosuid,noexec /dev/shm

  # Debian enables AppArmor by default; just check it.
  [[ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" == "Y" ]] \
    || warn "AppArmor is not enabled in the kernel."
}

# Logs sudo commands, disables rpcbind and LLMNR.
step_misc() {
  log "9/10 Sudo logging, unused services"
  local f=/etc/sudoers.d/99-logging
  echo 'Defaults logfile=/var/log/sudo.log' > "$f.tmp"
  chmod 440 "$f.tmp"
  visudo -cqf "$f.tmp" || { rm -f "$f.tmp"; die "Invalid sudoers snippet."; }
  mv "$f.tmp" "$f"

  systemctl disable --now rpcbind.socket rpcbind.service >/dev/null 2>&1 || true

  # LLMNR (local-network name resolution, port 5355 on all interfaces) is useless on a VPS.
  if systemctl is-active --quiet systemd-resolved; then
    install -d -m 755 /etc/systemd/resolved.conf.d
    printf '[Resolve]\nLLMNR=no\n' > /etc/systemd/resolved.conf.d/no-llmnr.conf
    systemctl restart systemd-resolved
  fi
}

# Prints the effective SSH, firewall and fail2ban state and open ports.
step_verify() {
  log "10/10 Checks"
  echo "--- sshd"
  sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|port|permitrootlogin|allowusers|allowagentforwarding) '
  echo "--- $AGENT_USER keys"
  sshd -T -C "user=$AGENT_USER,host=localhost,addr=127.0.0.1" | grep -i '^authorizedkeysfile '
  cut -c1-80 "$KEYS_DIR/$AGENT_USER"
  echo "--- ufw"
  ufw status verbose
  echo "--- fail2ban"
  fail2ban-client status sshd || warn "fail2ban is not ready yet."
  echo "--- listening ports"
  ss -tulpn
  if [[ -f /var/run/reboot-required ]]; then
    warn "Reboot required (kernel/libc update): sudo reboot"
  fi
  log "Hardening done. Next: setup-agent.sh as $AGENT_USER (docs/vps-setup.md)."
}

# Parses arguments and runs all steps in order.
main() {
  case "${1:-}" in
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    "") ;;
    *) die "Unknown argument: $1" ;;
  esac
  preflight
  step_base
  step_unattended
  step_agent_user
  step_sshd
  step_ufw
  step_fail2ban
  step_swap_journald
  step_kernel
  step_misc
  step_verify
}

main "$@"
