#!/usr/bin/env bash
# Clones missing child repos (repos.conf), regenerates the VS Code workspace and links the overlay.
# Managed by dotfiles/orchestrator: local edits are overwritten by `make update`.
set -euo pipefail
cd "$(dirname "$0")/.."
{ grep -vE '^\s*(#|$)' repos.conf || true; } | while read -r alias dir url branch; do
  if [[ -d "$dir/.git" ]]; then echo "ok     $dir"
  else git clone ${branch:+-b "$branch"} "$url" "$dir" </dev/null || echo "FAIL   $alias: clone of $url failed"; fi
done
./scripts/gen-workspace.sh
./scripts/overlay.sh link
