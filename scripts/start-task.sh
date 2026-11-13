#!/usr/bin/env bash
# Start or resume a task: worktree on branch task/<slug>, then a coordinator session in it.
#
# Usage (as the factory user, inside a Herdr or tmux pane):
#   start-task.sh <owner/repo> <slug> [spec.md]   # spec.md is copied to specs/<slug>.md
#   start-task.sh <owner/repo> <slug>             # resume
set -euo pipefail

[[ $# -ge 2 ]] || { sed -n '4,6p' "$0" >&2; exit 2; }
repo=$1 slug=$2 spec=${3:-}
[[ $slug =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "Slug: lowercase letters, digits, dashes." >&2; exit 2; }

clone="$HOME/projects/${repo#*/}"
wt="$HOME/worktrees/${repo#*/}-$slug"

[[ -d $clone ]] || gh repo clone "$repo" "$clone"
git -C "$clone" fetch -q origin

# Resuming needs the spec in the worktree or committed on the task branch.
if [[ -z $spec && ! -f $wt/specs/$slug.md ]] &&
   ! git -C "$clone" cat-file -e "task/$slug:specs/$slug.md" 2>/dev/null; then
  echo "No spec for '$slug': pass spec.md to start a new task." >&2; exit 1
fi

if [[ ! -d $wt ]]; then
  if git -C "$clone" show-ref -q --verify "refs/heads/task/$slug"; then
    git -C "$clone" worktree add "$wt" "task/$slug"
  else
    git -C "$clone" worktree add --no-track -b "task/$slug" "$wt" origin/HEAD
  fi
fi
[[ -z $spec ]] || install -D -m 644 "$spec" "$wt/specs/$slug.md"

cd "$wt"
exec claude --agent coordinator --dangerously-skip-permissions \
  "Task slug: $slug. Spec: specs/$slug.md. Start, or resume from docs/tasks/$slug/tasks.md if it exists."
