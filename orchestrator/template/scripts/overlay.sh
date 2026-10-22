#!/usr/bin/env bash
# overlay.sh — links the AI files in overlay/<alias>/ into the child repos and their worktrees.
#   overlay.sh link                 adopt+link in all repos and worktrees, install hooks
#   overlay.sh here <alias> <dir>   link into one directory (used by the post-checkout hook)
#   overlay.sh status               show git status of child repos and worktrees
# Managed by dotfiles/orchestrator: local edits are overwritten by `make update`.
set -euo pipefail
ORCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ORCH/overlay/manifest"
say() { printf '  %-8s %s\n' "$1" "$2"; }

repos() { grep -vE '^\s*(#|$)' "$ORCH/repos.conf" | awk '{print $1, $2}'; }
paths_for() { grep -vE '^\s*(#|$)' "$MANIFEST" | awk -v a="$1" '$1=="*"||$1==a {print $2}'; }
worktrees_of() { git -C "$1" worktree list --porcelain | awk '/^worktree /{print substr($0,10)}'; }

link_dir() { # <alias> <target-dir>
  local alias="$1" tgt; tgt="$(cd "$2" && pwd)"
  local ov="$ORCH/overlay/$alias"
  local common; common="$(cd "$tgt" && cd "$(git rev-parse --git-common-dir)" && pwd)"
  local excl="$common/info/exclude"; mkdir -p "$(dirname "$excl")"; touch "$excl"
  echo "[$alias] ${tgt#$ORCH/}"
  while read -r p; do
    [[ -n "$p" ]] || continue
    local dst="$tgt/$p" src="$ov/$p"
    if [[ -n "$(git -C "$tgt" ls-files -- "$p" | head -1)" ]]; then
      say "tracked" "$p (already versioned in the repo: left untouched)"; continue; fi
    grep -qxF "/$p" "$excl" || echo "/$p" >>"$excl"
    if [[ -L "$dst" ]]; then rm "$dst"
    elif [[ -e "$dst" ]]; then
      if [[ ! -e "$src" ]]; then mkdir -p "$(dirname "$src")"; mv "$dst" "$src"; say "adopt" "$p -> overlay/$alias/$p"
      else say "CONFL" "$p exists both in the repo and in overlay: resolve manually"; continue; fi
    fi
    [[ -e "$src" ]] || continue
    mkdir -p "$(dirname "$dst")"
    ln -s "$(realpath --relative-to="$(dirname "$dst")" "$src")" "$dst"; say "link" "$p"
  done < <(paths_for "$alias")
}

install_hook() { # <alias> <repo-dir>
  local alias="$1" repo="$2" hp hooks
  hp="$(git -C "$repo" config --get core.hooksPath || true)"
  if [[ -n "$hp" ]]; then
    echo "  WARN     $alias uses core.hooksPath=$hp (husky?): hook not installed, run 'make overlay' after each new worktree"; return; fi
  hooks="$(cd "$repo" && cd "$(git rev-parse --git-common-dir)" && pwd)/hooks"; mkdir -p "$hooks"
  local h="$hooks/post-checkout"
  # Any "<name> overlay hook" marker is ours (older orchestrators used the project name).
  if [[ -e "$h" ]] && ! grep -q ' overlay hook (local, not versioned)' "$h"; then
    echo "  WARN     $alias already has a post-checkout hook: add the overlay.sh call manually"; return; fi
  cat >"$h" <<HOOK
#!/bin/sh
# orchestrator overlay hook (local, not versioned): links AI files into new worktrees
[ "\$3" = "1" ] || exit 0
common=\$(cd "\$(git rev-parse --git-common-dir)" && pwd)
orch=\$(dirname "\$(dirname "\$common")")
[ -x "\$orch/scripts/overlay.sh" ] && "\$orch/scripts/overlay.sh" here $alias "\$(pwd)" || true
HOOK
  chmod +x "$h"
}

case "${1:-link}" in
  link)
    while read -r alias dir; do
      [[ -d "$ORCH/$dir/.git" ]] || { echo "[$alias] $dir missing (run make bootstrap)"; continue; }
      mkdir -p "$ORCH/overlay/$alias"
      install_hook "$alias" "$ORCH/$dir"
      while read -r wt; do [[ -d "$wt" ]] && link_dir "$alias" "$wt"; done < <(worktrees_of "$ORCH/$dir")
    done < <(repos) ;;
  here) link_dir "$2" "$3" ;;
  status)
    while read -r alias dir; do
      [[ -d "$ORCH/$dir/.git" ]] || continue
      while read -r wt; do
        [[ -d "$wt" ]] || continue
        printf '[%s] %-32s %s\n' "$alias" "${wt#$ORCH/}" "$(git -C "$wt" branch --show-current)"
        git -C "$wt" status --short | sed 's/^/    /'
      done < <(worktrees_of "$ORCH/$dir")
    done < <(repos) ;;
  *) echo "usage: overlay.sh [link|here <alias> <dir>|status]"; exit 1 ;;
esac
