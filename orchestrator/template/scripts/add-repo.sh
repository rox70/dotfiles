#!/usr/bin/env bash
# add-repo.sh <alias> <remote-url> [default-branch] [folder]
# Registers a child repo in repos.conf, then clones it and links the overlay (bootstrap).
# Managed by dotfiles/orchestrator: local edits are overwritten by `make update`.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# -ge 2 ]] || { echo "usage: add-repo.sh <alias> <remote-url> [default-branch] [folder]"; exit 1; }
alias="$1" url="$2" branch="${3:-}" dir="${4:-$(basename "${2%.git}")}"
[[ "$alias" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { echo "invalid alias: $alias (use [a-z0-9_-])"; exit 1; }
if grep -vE '^\s*(#|$)' repos.conf | awk -v a="$alias" -v d="$dir" '$1==a||$2==d{f=1} END{exit !f}'; then
  echo "alias '$alias' or folder '$dir' already in repos.conf"; exit 1; fi
printf '%-8s %-28s %s %s\n' "$alias" "$dir" "$url" "$branch" | sed 's/ *$//' >>repos.conf
mkdir -p "overlay/$alias"
echo "added  $alias -> $dir ($url${branch:+ @ $branch})"
echo "TODO   describe '$alias' in the repository table of CLAUDE.md"
./scripts/bootstrap.sh
