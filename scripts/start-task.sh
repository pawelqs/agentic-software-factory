#!/usr/bin/env bash
# Start or resume a task: worktree on branch task/<n>-<name>, then a coordinator session in it.
#
# Usage (as the factory user, inside a Herdr or tmux pane):
#   start-task.sh <owner/repo> <name> <spec.md>   # new task: next free <n>, spec copied to docs/features/<n>-<name>/spec.md
#   start-task.sh <owner/repo> <name>             # resume
set -euo pipefail

die() { printf '[error] %s\n' "$*" >&2; exit 1; }

[[ $# -ge 2 ]] || die "Usage: start-task.sh <owner/repo> <name> [spec.md]"
repo=$1 name=$2 spec=${3:-}
[[ $name =~ ^[a-z][a-z0-9-]*$ ]] || die "Name: lowercase letters, digits, dashes; starts with a letter."
[[ -z $spec || -f $spec ]] || die "No such spec file: $spec"

clone="$HOME/projects/${repo#*/}"
[[ -d $clone ]] || gh repo clone "$repo" "$clone"
git -C "$clone" fetch -q --prune origin
git -C "$clone" worktree prune

# Task branches, local and remote, as <n>-<name>.
task_refs() {
  git -C "$clone" for-each-ref --format='%(refname:lstrip=-1)' refs/heads/task/ refs/remotes/origin/task/
}

slug=$(task_refs | grep -E "^[0-9]{3}-$name\$" | head -n1 || true)
if [[ -z $slug ]]; then
  [[ -n $spec ]] || die "No task '$name' to resume: pass spec.md to start a new one."
  last=$({ git -C "$clone" ls-tree --name-only origin/HEAD docs/features/ 2>/dev/null | sed 's#.*/##'; task_refs; } |
    sed -n 's/^\([0-9]\{3\}\)-.*/\1/p' | sort -n | tail -n1)
  printf -v slug '%03d-%s' $((10#${last:-0} + 1)) "$name"
fi

wt="$HOME/worktrees/${repo#*/}-$slug"
if [[ ! -d $wt ]]; then
  if git -C "$clone" show-ref -q --verify "refs/heads/task/$slug"; then
    git -C "$clone" worktree add "$wt" "task/$slug"
  elif git -C "$clone" show-ref -q --verify "refs/remotes/origin/task/$slug"; then
    git -C "$clone" worktree add --track -b "task/$slug" "$wt" "origin/task/$slug"
  else
    git -C "$clone" worktree add --no-track -b "task/$slug" "$wt" origin/HEAD
  fi
fi

# Temporary agent files stay out of git without touching the project's .gitignore.
exclude="$(git -C "$clone" rev-parse --path-format=absolute --git-common-dir)/info/exclude"
grep -qxF '/.agents/' "$exclude" 2>/dev/null || echo '/.agents/' >> "$exclude"

[[ -z $spec ]] || install -D -m 644 "$spec" "$wt/docs/features/$slug/spec.md"
[[ -f $wt/docs/features/$slug/spec.md ]] || die "No spec at $wt/docs/features/$slug/spec.md: pass spec.md."

cd "$wt"
exec claude --agent coordinator --dangerously-skip-permissions \
  "Task slug: $slug. Spec: docs/features/$slug/spec.md. Start, or resume from docs/features/$slug/tasks.md if it exists."
