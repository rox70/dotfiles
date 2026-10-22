#!/bin/sh
# Nothing to install at image build time: this Feature only contributes the
# volume mounts declared in devcontainer-feature.json. Linking them to each
# tool's config directory (~/.claude, ~/.config/gh, ...) is done by the
# dotfiles install.sh at container creation, once the volumes are mounted.
set -e
echo "shared-logins: mounts /tmp/.claude-host, /tmp/.claude-accounts and /tmp/.shared-logins (named volumes)."
