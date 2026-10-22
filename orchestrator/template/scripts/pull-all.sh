#!/usr/bin/env bash
# Fast-forwards every cloned child repo.
# Managed by dotfiles/orchestrator: local edits are overwritten by `make update`.
set -euo pipefail
cd "$(dirname "$0")/.."
{ grep -vE '^\s*(#|$)' repos.conf || true; } | while read -r alias dir _; do
  [[ -d "$dir/.git" ]] || continue
  echo "== $alias"; git -C "$dir" pull --ff-only </dev/null
done
