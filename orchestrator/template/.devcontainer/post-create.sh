#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
git config --global --add safe.directory '*'
# SSH keys from the host (read-only mount) -> writable copy with correct permissions
if [[ -d /tmp/.ssh-host ]]; then
  mkdir -p "$HOME/.ssh" && cp -rn /tmp/.ssh-host/. "$HOME/.ssh/" || true
  chmod 700 "$HOME/.ssh"; chmod 600 "$HOME"/.ssh/id_* 2>/dev/null || true
fi
ssh-keyscan -t ed25519,rsa bitbucket.org github.com >>"$HOME/.ssh/known_hosts" 2>/dev/null || true
# Claude Code normally comes from dotfiles install.sh; fall back to npm if dotfiles are not configured
command -v claude >/dev/null || npm i -g @anthropic-ai/claude-code || true
# clone missing child repos, regenerate the workspace, link the AI overlay
./scripts/bootstrap.sh || true
# reinstall the add-ons selected in addons.conf at their latest versions (make addons-sync)
[[ -x scripts/addon.sh ]] && { ./scripts/addon.sh sync || true; }
