#!/usr/bin/env bash
# Hardening of the factory VPS (OVH VPS-1, Debian 13). Based on the homelab RPi hardening script.
#
# Usage (from the laptop):
#   scp scripts/harden.sh debian@<IP>: && ssh -t debian@<IP> 'sudo bash harden.sh'
# Then install the agent tools as the agent user: setup-agent.sh
#
# Idempotent: safe to run again. Manual steps: docs/vps-setup.md
set -euo pipefail

HOSTNAME_NEW="factory"
ADMIN_USER="debian"
AGENT_USER="factory"
SWAP_SIZE="4G"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

preflight() {
  [[ $EUID -eq 0 ]] || die "Run as root: sudo bash harden.sh"
  grep -q '^ID=debian' /etc/os-release || die "This script expects Debian."
  id "$ADMIN_USER" >/dev/null 2>&1 || die "User $ADMIN_USER does not exist."
  [[ -s "/home/$ADMIN_USER/.ssh/authorized_keys" ]] \
    || die "/home/$ADMIN_USER/.ssh/authorized_keys is empty. Run 'ssh-copy-id ${ADMIN_USER}@<IP>' first, otherwise disabling passwords locks you out."
}

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
    ufw fail2ban python3-systemd unattended-upgrades apparmor \
    git tmux build-essential ripgrep jq curl ca-certificates

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

step_unattended() {
  log "2/10 Unattended upgrades (Debian defaults: stable + security, no auto-reboot)"
  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
  systemctl enable --now unattended-upgrades >/dev/null
}

step_agent_user() {
  log "3/10 User $AGENT_USER (no sudo)"
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
  log "4/10 SSH hardening"
  # 10-* is read before 50-cloud-init.conf; the first value wins in sshd.
  local conf=/etc/ssh/sshd_config.d/10-hardening.conf
  cat > "$conf" <<EOF
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers $ADMIN_USER $AGENT_USER
LoginGraceTime 20
AllowAgentForwarding no
X11Forwarding no
EOF
  if ! sshd -t; then
    rm -f "$conf"
    die "sshd config test failed. Removed $conf, not reloading."
  fi
  systemctl reload ssh
}

step_ufw() {
  log "5/10 Firewall (ufw)"
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw limit 22/tcp comment 'ssh' >/dev/null
  ufw --force enable >/dev/null
}

step_fail2ban() {
  log "6/10 fail2ban"
  cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 3
findtime = 600
bantime = 3600
EOF
  systemctl enable fail2ban >/dev/null
  systemctl restart fail2ban
}

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

step_misc() {
  log "9/10 Sudo logging, unused services"
  local f=/etc/sudoers.d/99-logging
  echo 'Defaults logfile=/var/log/sudo.log' > "$f.tmp"
  chmod 440 "$f.tmp"
  visudo -cqf "$f.tmp" || { rm -f "$f.tmp"; die "Invalid sudoers snippet."; }
  mv "$f.tmp" "$f"

  systemctl disable --now rpcbind.socket rpcbind.service >/dev/null 2>&1 || true
}

step_verify() {
  log "10/10 Checks"
  echo "--- sshd"
  sshd -T | grep -Ei '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin|allowusers|maxauthtries|allowagentforwarding) '
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

main() {
  case "${1:-}" in
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
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
