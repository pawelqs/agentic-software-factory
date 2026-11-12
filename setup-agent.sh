#!/usr/bin/env bash
# Agent tools for the factory user: mise + Node, Claude Code, uv, Herdr, git config, shell env.
#
# Run as the agent user (no sudo), after harden.sh:
#   scp setup-agent.sh factory@<IP>: && ssh factory@<IP> 'bash setup-agent.sh'
#
# Idempotent: safe to run again. Manual steps: docs/vps-setup.md
set -euo pipefail

GIT_NAME="ellie-7894"
GIT_EMAIL="355491988+ellie-7894@users.noreply.github.com"
CFG="$HOME/.config/factory"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn] %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31m[error] %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || die "Run as the agent user, not root."
cd ~
export PATH="$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH"

log "1/4 mise + Node, Claude Code, uv, Herdr"
[[ -x ~/.local/bin/mise ]] || curl -fsSL https://mise.run | sh
mise use -g node@lts
[[ -x ~/.local/bin/claude ]] || curl -fsSL https://claude.ai/install.sh | bash
[[ -x ~/.local/bin/uv ]] || curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
# Herdr is not critical: a broken installer must not stop the setup.
if ! command -v herdr >/dev/null && ! curl -fsSL https://herdr.dev/install.sh | sh; then
  warn "Herdr install failed. See https://herdr.dev/docs/install/ (tmux is installed as a fallback)."
fi

log "2/4 git"
git config --global --unset-all credential.https://github.com.helper || true
git config --global --add credential.https://github.com.helper ''
git config --global --add credential.https://github.com.helper '!gh auth git-credential'
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main

log "3/4 Shell environment"
install -d -m 700 "$HOME/.config" "$CFG"
cat > "$CFG/shellrc" <<'EOF'
# Managed by setup-agent.sh. Sourced at the top of ~/.bashrc, so it also works for 'ssh factory cmd'.
for d in "$HOME/.local/share/mise/shims" "$HOME/.local/bin"; do
  case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
export PATH
if [ -r "$HOME/.config/factory/env" ]; then
  set -a; . "$HOME/.config/factory/env"; set +a
fi
EOF

if [[ ! -f "$CFG/env" ]]; then
  cat > "$CFG/env" <<'EOF'
# Factory secrets. chmod 600, never commit. Exported by ~/.config/factory/shellrc.
# CLAUDE_CODE_OAUTH_TOKEN=   # from 'claude setup-token' (run on the laptop)
# GH_TOKEN=                  # classic PAT of ellie-7894 "factory", scope: repo only
EOF
fi
chmod 600 "$CFG/env"

touch ~/.bashrc
if ! grep -qF '.config/factory/shellrc' ~/.bashrc; then
  { echo '[ -r "$HOME/.config/factory/shellrc" ] && . "$HOME/.config/factory/shellrc"'; cat ~/.bashrc; } > ~/.bashrc.new
  mv ~/.bashrc.new ~/.bashrc
fi

log "4/4 Checks (fresh login shell)"
env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" PATH=/usr/bin:/bin bash -lc '
  for c in node claude uv gh git tmux herdr; do
    printf "%-7s " "$c"
    if ! command -v "$c" >/dev/null; then echo MISSING; continue; fi
    if [ "$c" = tmux ]; then tmux -V; else "$c" --version 2>&1 | head -n1; fi
  done
  id
'
log "Agent setup done. Next: secrets in $CFG/env (docs/vps-setup.md)."
