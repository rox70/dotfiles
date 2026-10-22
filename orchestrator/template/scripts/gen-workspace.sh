#!/usr/bin/env bash
# Regenerates <orchestrator>.code-workspace from repos.conf (orchestrator + one folder per child repo).
# Managed by dotfiles/orchestrator: local edits are overwritten by `make update`.
set -euo pipefail
cd "$(dirname "$0")/.."
name="$(basename "$PWD")"
{
  printf '{\n  "folders": [\n    { "name": "%s (orchestrator)", "path": "." }' "$name"
  { grep -vE '^\s*(#|$)' repos.conf || true; } | while read -r alias dir _; do
    printf ',\n    { "name": "%s", "path": "%s" }' "$alias" "$dir"
  done
  printf '\n  ],\n  "settings": {\n'
  printf '    "git.autoRepositoryDetection": "subFolders",\n'
  printf '    "git.repositoryScanMaxDepth": 1\n  }\n}\n'
} >"$name.code-workspace"
echo "write  $name.code-workspace"
