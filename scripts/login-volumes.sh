#!/bin/bash
# Manage the Docker named volumes that hold the shared CLI logins
# (shared-logins Feature, features/src/ in this repo): claude-host (default
# Claude account), claude-accounts (one subdirectory per extra Claude account)
# and shared-logins (one subdirectory per other tool, e.g. gh).
#
#   seed <src-volume>  copy an existing ~/.claude volume (e.g. a project's own
#                      <project>-claude-config) into claude-host, so the
#                      default account needs no new login. Works anywhere
#                      the Docker CLI reaches the engine (host or container).
#   backup             copy all the volumes to ~/.claude-login-backup/<volume>/
#   restore            copy ~/.claude-login-backup/<volume>/ back into them
#
# backup/restore bind-mount a path of the Docker HOST: run them on the host
# (e.g. the WSL shell), not inside a devcontainer. The backup holds live
# credentials: it is created with mode 700 and must never be put in a repo.
set -e

VOLUMES=(claude-host claude-accounts shared-logins)
IMAGE="${CLAUDE_VOLUMES_IMAGE:-alpine}"
BACKUP_ROOT="$HOME/.claude-login-backup"

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

require_host() {
    if [ -f /.dockerenv ]; then
        echo "Refusing to run '$1' inside a container: the backup path would be resolved on the Docker host, not here. Run it from the host shell." >&2
        exit 1
    fi
}

copy_volume() { # <src-mount-spec> <dst-mount-spec>
    docker run --rm -v "$1:/src:ro" -v "$2:/dst" "$IMAGE" sh -c 'cp -a /src/. /dst/'
}

case "$1" in
    seed)
        [ -n "$2" ] || usage
        docker volume inspect "$2" > /dev/null
        docker volume create claude-host > /dev/null
        copy_volume "$2" claude-host
        echo "Seeded claude-host from $2."
        ;;
    backup)
        require_host backup
        for v in "${VOLUMES[@]}"; do
            docker volume inspect "$v" > /dev/null 2>&1 || { echo "Skipping $v: volume not found."; continue; }
            mkdir -p "$BACKUP_ROOT/$v" && chmod 700 "$BACKUP_ROOT" "$BACKUP_ROOT/$v"
            copy_volume "$v" "$BACKUP_ROOT/$v"
            echo "Backed up $v to $BACKUP_ROOT/$v"
        done
        ;;
    restore)
        require_host restore
        for v in "${VOLUMES[@]}"; do
            [ -d "$BACKUP_ROOT/$v" ] || { echo "Skipping $v: no backup in $BACKUP_ROOT/$v."; continue; }
            docker volume create "$v" > /dev/null
            copy_volume "$BACKUP_ROOT/$v" "$v"
            echo "Restored $v from $BACKUP_ROOT/$v"
        done
        ;;
    *)
        usage
        ;;
esac
