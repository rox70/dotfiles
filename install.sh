#!/bin/bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Everything outside a container stays inside the user's profile ($HOME):
# no sudo, no system-wide packages, no shared /tmp paths -- the same script
# must be safe for any user of a shared Linux server. Inside a devcontainer
# (an isolated, disposable system) the package manager and the fixed /tmp
# mount points of the shared-logins Feature are used.
in_container() {
    [ -f /.dockerenv ] || [ -f /run/.containerenv ]
}
mkdir -p "$HOME/.local/bin"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac

# --- 0. Preflight: required tools ---
# jq is needed both here (settings merge) and at runtime by the statusline
# scripts; npm installs ccstatusline (and the Claude CLI when curl is
# missing). Try to install jq (package manager in a container, user-local
# binary on a host), and collect every
# remaining problem so it is reported loudly (at start and again at the end:
# under VS Code's dotfiles support this output only lands in the
# "Dev Containers" log, easy to miss).
WARNINGS=()
warn() {
    WARNINGS+=("$1")
    printf '\033[01;33m[dotfiles] WARNING: %s\033[00m\n' "$1" >&2
}

as_root() {
    if [ "$(id -u)" = 0 ]; then
        "$@"
    elif command -v sudo &> /dev/null && sudo -n true 2> /dev/null; then
        sudo "$@"
    else
        return 1
    fi
}

# --- 0a. Stale checkout guard ---
# In a container ~/.claude is the claude-host volume shared by every
# devcontainer: an install.sh from an old checkout would overwrite the newer
# scripts and commands there (and bring back retired ones) for all of them.
# Stop when this checkout is behind origin's default branch; an unreachable
# remote only warns. DOTFILES_ALLOW_STALE=1 skips the check.
check_not_stale() {
    [ "${DOTFILES_ALLOW_STALE:-0}" = 1 ] && return 0
    git -C "$DOTFILES_DIR" rev-parse --git-dir &> /dev/null || return 0
    git -C "$DOTFILES_DIR" remote get-url origin &> /dev/null || return 0
    local fetch=(git -C "$DOTFILES_DIR" fetch -q origin)
    command -v timeout &> /dev/null && fetch=(timeout 20 "${fetch[@]}")
    if ! "${fetch[@]}" 2> /dev/null; then
        warn "could not fetch origin: not checking whether this dotfiles checkout is up to date."
        return 0
    fi
    local upstream behind
    upstream="$(git -C "$DOTFILES_DIR" symbolic-ref -q --short refs/remotes/origin/HEAD || echo origin/main)"
    behind="$(git -C "$DOTFILES_DIR" rev-list --count "HEAD..$upstream" 2> /dev/null || echo 0)"
    if [ "$behind" -gt 0 ]; then
        printf '\033[01;31m[dotfiles] ERROR: %s is %s commit(s) behind %s.\033[00m\n' "$DOTFILES_DIR" "$behind" "$upstream" >&2
        echo "Run 'git -C $DOTFILES_DIR pull' first (or DOTFILES_ALLOW_STALE=1 ./install.sh to install this version anyway)." >&2
        exit 1
    fi
}
check_not_stale

install_jq_user_local() {
    local arch
    case "$(uname -m)" in
        x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) return 1 ;;
    esac
    command -v curl &> /dev/null || return 1
    curl -fsSL --retry 3 -o "$HOME/.local/bin/jq.tmp" \
        "https://github.com/jqlang/jq/releases/latest/download/jq-linux-$arch" \
        && chmod +x "$HOME/.local/bin/jq.tmp" \
        && "$HOME/.local/bin/jq.tmp" --version > /dev/null \
        && mv "$HOME/.local/bin/jq.tmp" "$HOME/.local/bin/jq"
    local rc=$?
    rm -f "$HOME/.local/bin/jq.tmp"
    return $rc
}

if ! command -v jq &> /dev/null; then
    echo "jq not found: trying to install it..."
    if in_container; then
        if command -v apt-get &> /dev/null; then
            as_root apt-get update -qq && as_root apt-get install -y -qq jq
        elif command -v apk &> /dev/null; then
            as_root apk add --no-cache jq
        elif command -v dnf &> /dev/null; then
            as_root dnf install -y -q jq
        fi > /dev/null 2>&1 || true
    else
        install_jq_user_local || true
    fi
fi
command -v jq &> /dev/null \
    || warn "jq not found and could not be installed: statusline will show only account and git info (no model, usage, context), subagent statusline stays empty, settings.json merge skipped."
# Node.js/npm (ccstatusline, the npm fallback for the Claude CLI, the AI
# add-ons): when npm is missing, install the latest LTS from the official
# nodejs.org tarball (checksum-verified) into ~/.local/node -- user-local, no
# root, same on a host and in a container. Distribution packages are often
# far too old (Ubuntu 22.04 ships Node 12). An existing Node (system package,
# nvm, a hand-unpacked tarball, a devcontainer Feature) is never touched.
NODE_HOME="$HOME/.local/node"
install_node_user_local() {
    local arch version file base tmp rc tool
    case "$(uname -m)" in
        x86_64) arch=x64 ;; aarch64|arm64) arch=arm64 ;; *) return 1 ;;
    esac
    for tool in curl jq tar sha256sum; do
        command -v "$tool" &> /dev/null || return 1
    done
    version="$(curl -fsSL --retry 3 https://nodejs.org/dist/index.json \
        | jq -r '[.[] | select(.lts != false)][0].version')"
    case "$version" in v[0-9]*) ;; *) return 1 ;; esac
    file="node-$version-linux-$arch.tar.gz"
    base="https://nodejs.org/dist/$version"
    tmp="$(mktemp -d "$HOME/.local/.node-install.XXXXXX")"
    curl -fsSL --retry 3 -o "$tmp/$file" "$base/$file" \
        && curl -fsSL --retry 3 -o "$tmp/SHASUMS256.txt" "$base/SHASUMS256.txt" \
        && (cd "$tmp" && grep "  $file\$" SHASUMS256.txt | sha256sum -c --status) \
        && mkdir "$tmp/node" \
        && tar -xzf "$tmp/$file" -C "$tmp/node" --strip-components=1 \
        && "$tmp/node/bin/node" --version > /dev/null \
        && rm -rf "$NODE_HOME" \
        && mv "$tmp/node" "$NODE_HOME"
    rc=$?
    rm -rf "$tmp"
    [ $rc -eq 0 ] && echo "Installed Node.js $version in $NODE_HOME."
    return $rc
}

if ! command -v npm &> /dev/null; then
    echo "npm not found: installing the latest Node.js LTS in $NODE_HOME..."
    install_node_user_local || true
fi
if [ -x "$NODE_HOME/bin/npm" ]; then
    case ":$PATH:" in *":$NODE_HOME/bin:"*) ;; *) export PATH="$NODE_HOME/bin:$PATH" ;; esac
fi
command -v npm &> /dev/null \
    || warn "npm not found and Node.js could not be installed: ccstatusline cannot be installed. Install Node.js by hand (https://nodejs.org)."

# npm -g into the user's profile when the global prefix is not writable
# (system Node on a host); nvm/fnm prefixes and containers keep plain -g.
npm_install_global() {
    local prefix
    prefix="$(npm prefix -g 2>/dev/null)"
    if [ -n "$prefix" ] && { [ -w "$prefix/lib/node_modules" ] || { [ ! -e "$prefix/lib/node_modules" ] && [ -w "$prefix" ]; }; }; then
        npm install -g "$@"
    else
        npm install -g --prefix "$HOME/.local" "$@"
    fi
}

# --- 0b. Shared-login volumes (host with Docker) ---
# The shared-logins Feature mounts the named volumes below. A single-container
# devcontainer makes Docker create them on first use, but a compose-based one
# declares them `external` (features/README.md) and fails to start while they
# are missing -- e.g. when it is the first devcontainer opened on this engine.
# Create them up front: `docker volume create` is a no-op for an existing
# volume. Keep the names in sync with features/src/shared-logins/.
SHARED_LOGIN_VOLUMES="claude-host claude-accounts shared-logins"
if ! in_container && command -v docker &> /dev/null; then
    if docker info &> /dev/null; then
        for vol in $SHARED_LOGIN_VOLUMES; do
            docker volume create "$vol" > /dev/null \
                || warn "could not create the Docker volume $vol: a compose-based devcontainer using the shared logins will fail to start until it exists."
        done
    else
        warn "docker is installed but its engine is not reachable: shared-login volumes not created. Re-run install.sh once Docker is running (needed before opening a compose-based devcontainer first)."
    fi
fi

# --- 1. Host Symlink Management / Cross-Project Session Persistence ---
# /tmp/.claude-host is a per-devcontainer mountpoint: whichever host directory
# a project's docker-compose.yml binds there becomes this container's
# ~/.claude and ~/.claude.json. Point that mount at the SAME host directory
# (e.g. ~/.claude-host on the host) in every project's compose file and one
# `claude login` is shared -- and survives every rebuild -- across all of
# them, with nothing project-specific to install here.
#
# A bare (non-container) host uses ~/.claude-host directly, its own real
# on-disk equivalent of what a container would have mounted there. Never
# /tmp on a host: it is shared by every user, so a /tmp/.claude-host created
# by someone else would capture this user's login.
if in_container && [ -d /tmp/.claude-host ]; then
    HOST_CLAUDE="/tmp/.claude-host"
else
    HOST_CLAUDE="$HOME/.claude-host"
fi
TARGET_CLAUDE="$HOME/.claude"
TARGET_CLAUDE_JSON="$HOME/.claude.json"

# A devcontainer may instead persist ~/.claude in its own named volume
# (mounts: source=<name>,target=~/.claude,type=volume). That directory is a
# mountpoint: it can't be moved aside, and it already survives rebuilds, so
# leave it (and the session file next to it) alone. A symlink is skipped:
# mountpoint follows it, so ~/.claude already linked to the mounted
# /tmp/.claude-host would look like such a volume.
CLAUDE_IS_MOUNT=0
if [ ! -L "$TARGET_CLAUDE" ] && command -v mountpoint &> /dev/null && mountpoint -q "$TARGET_CLAUDE" 2>/dev/null; then
    CLAUDE_IS_MOUNT=1
    echo "$TARGET_CLAUDE is a mountpoint (e.g. a devcontainer volume): not linking it to $HOST_CLAUDE."
fi

# Named volumes (shared-logins Feature) are created root-owned and are
# shared by every devcontainer on the engine: files written by a container
# running as another user (e.g. remoteUser root) are often mode 600, so a
# non-root remoteUser fails to read settings.json, history, sessions, the
# gh token...
# Hand the whole tree to the container user. Root reads everything anyway
# and must not take the files back, or it would lock the non-root users out.
if in_container && [ "$(id -u)" != 0 ]; then
    for shared in /tmp/.claude-host /tmp/.claude-accounts /tmp/.shared-logins; do
        [ -d "$shared" ] || continue
        [ -n "$(find "$shared" ! -user "$(id -u)" -print -quit 2> /dev/null)" ] || continue
        as_root chown -R "$(id -u):$(id -g)" "$shared" \
            || warn "$shared holds files not owned by $(id -un) and could not be chowned: Claude Code, gh, ... may fail to read their settings or login. Use the same remoteUser in every devcontainer."
    done
fi

if [ "$CLAUDE_IS_MOUNT" = 0 ] && [ -d "$HOST_CLAUDE" ] && [ ! -L "$TARGET_CLAUDE" ]; then
    echo "Linking Claude configuration from host..."
    # Back up rather than delete: on a bare host $TARGET_CLAUDE may already be
    # a real, live-in-use config directory (not just container scratch state).
    [ -e "$TARGET_CLAUDE" ] && mv "$TARGET_CLAUDE" "$TARGET_CLAUDE.bak-$(date +%Y%m%d%H%M%S)"
    ln -s "$HOST_CLAUDE" "$TARGET_CLAUDE"
fi

if [ "$CLAUDE_IS_MOUNT" = 0 ] && [ -d "$HOST_CLAUDE" ] && [ ! -L "$TARGET_CLAUDE_JSON" ]; then
    echo "Linking Claude session file from host..."
    [ -e "$TARGET_CLAUDE_JSON" ] && mv "$TARGET_CLAUDE_JSON" "$TARGET_CLAUDE_JSON.bak-$(date +%Y%m%d%H%M%S)"
    ln -s "$HOST_CLAUDE/.claude.json" "$TARGET_CLAUDE_JSON"
fi

# Ensure required subdirectories exist (handling potential symlink)
mkdir -p "$TARGET_CLAUDE/scripts" "$TARGET_CLAUDE/commands" ~/.config/ccstatusline

# Personal settings live next to the login (in a container: the shared
# claude-host volume), so they follow the user to every devcontainer and are
# never part of this repo. Created once; edit it by hand afterwards. Initial
# values can be passed as env vars, e.g.
#   STATUSLINE_TZ=Europe/London ./install.sh
# (Account labels are not settings: they live in ~/.claude/account-labels,
# see claude-accounts.sh.)
DOTFILES_CONF="$TARGET_CLAUDE/dotfiles.conf"
if [ ! -f "$DOTFILES_CONF" ]; then
    cat > "$DOTFILES_CONF" <<EOF
# Personal dotfiles settings (sourced by the statusline).
# Time zone for the rate-limit reset times (e.g. Europe/London); empty = machine local time.
STATUSLINE_TZ="${STATUSLINE_TZ:-}"
EOF
    echo "Created $DOTFILES_CONF (personal settings: edit it to set your time zone)."
fi

# --- 2. Claude Code CLI Installation ---
# Prefer the official native installer (no Node/npm or root needed,
# auto-updates, installs to ~/.local/bin); fall back to npm without curl.
if command -v claude &> /dev/null; then
    echo "Claude CLI is already installed."
elif command -v curl &> /dev/null; then
    echo "Installing Claude Code CLI (native installer)..."
    # Download first, then run: with a plain "curl | bash" a failed download
    # just feeds bash an empty script, which exits 0 and hides the error.
    claude_installer="$(mktemp)"
    if curl -fsSL --retry 3 https://claude.ai/install.sh -o "$claude_installer" \
        && bash "$claude_installer"; then
        :
    else
        warn "Claude Code native installer failed: install it manually (https://code.claude.com/docs/en/setup)."
    fi
    rm -f "$claude_installer"
elif command -v npm &> /dev/null; then
    echo "Installing @anthropic-ai/claude-code via npm..."
    npm_install_global @anthropic-ai/claude-code \
        || warn "npm install of @anthropic-ai/claude-code failed."
else
    warn "Neither curl nor npm found: Claude Code CLI not installed."
fi

# --- 2b. Orchestrator commands (orch-new, orch-update) ---
# Symlinked (not copied) so a `git pull` of this repo updates them in place.
mkdir -p "$HOME/.local/bin"
for cmd in "$DOTFILES_DIR/orchestrator/bin/"*; do
    ln -sfn "$cmd" "$HOME/.local/bin/$(basename "$cmd")"
done

# --- 2c. GitHub CLI (gh) ---
# Official release binary into ~/.local/bin: same steps on a host and in any
# container image, no root or package repository needed.
install_gh_user_local() {
    local arch tag version tmp rc
    case "$(uname -m)" in
        x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) return 1 ;;
    esac
    command -v curl &> /dev/null || return 1
    # The asset name carries the version: resolve "latest" through its redirect.
    tag="$(curl -fsSL --retry 3 -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest)" || return 1
    version="${tag##*/v}"
    tmp="$(mktemp -d)"
    curl -fsSL --retry 3 "https://github.com/cli/cli/releases/download/v$version/gh_${version}_linux_$arch.tar.gz" \
        | tar -xz -C "$tmp" \
        && "$tmp/gh_${version}_linux_$arch/bin/gh" --version > /dev/null \
        && install -m 755 "$tmp/gh_${version}_linux_$arch/bin/gh" "$HOME/.local/bin/gh"
    rc=$?
    rm -rf "$tmp"
    return $rc
}

if command -v gh &> /dev/null; then
    echo "GitHub CLI is already installed."
else
    echo "Installing GitHub CLI (gh)..."
    install_gh_user_local \
        || warn "GitHub CLI (gh) could not be installed: install it manually (https://github.com/cli/cli#installation)."
fi

# --- 2d. Shared logins of other CLIs (gh, ...) ---
# In a container, each tool's config directory becomes a symlink to its own
# subdirectory of the shared-logins volume (shared-logins Feature), so one
# login per tool serves every devcontainer on the Docker engine and survives
# rebuilds. Another tool = one more link_shared_login line, no new Feature.
# On a host the tools keep their own config directories: nothing to do.
link_shared_login() { # <subdirectory> <config dir>
    local shared="/tmp/.shared-logins/$1" target="$2"
    [ -L "$target" ] && return 0
    mkdir -p "$shared" "$(dirname "$target")" || return 1
    if [ -e "$target" ]; then
        # A login made in this container before the volume existed seeds
        # an empty volume; the local copy is kept aside, never deleted.
        [ -z "$(ls -A "$shared")" ] && cp -a "$target/." "$shared/"
        mv "$target" "$target.bak-$(date +%Y%m%d%H%M%S)"
    fi
    ln -s "$shared" "$target" && echo "Linked $target to the shared $1 login."
}

if in_container; then
    if [ -d /tmp/.shared-logins ]; then
        link_shared_login gh "$HOME/.config/gh" \
            || warn "could not link ~/.config/gh to /tmp/.shared-logins/gh: gh logins stay local to this container."
    elif [ -d /tmp/.claude-host ]; then
        warn "the shared-logins volume is not mounted: gh logins stay local to this container. Replace the claude-shared-login Feature with ghcr.io/rox70/dotfiles/shared-logins:1 in dev.containers.defaultFeatures and rebuild."
    fi
fi

# The native installer and the orchestrator commands live in ~/.local/bin,
# which is not on PATH by default in every image: add it for new shells.
PATH_LINE='case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac'
for rc in ~/.bashrc ~/.zshrc ~/.profile; do
    if [ -f "$rc" ] && ! grep -qF "$PATH_LINE" "$rc"; then
        echo "$PATH_LINE" >> "$rc"
        echo "Added ~/.local/bin to PATH in $rc"
    fi
done

# On hosts whose sshd PAM stack has no pam_systemd (e.g. RHEL with domain users),
# SSH shells get no XDG_RUNTIME_DIR even when /run/user/<uid> exists (lingering):
# systemctl --user and rootless Docker then fail. Export it for new shells.
XDG_LINE='[ -n "$XDG_RUNTIME_DIR" ] || export XDG_RUNTIME_DIR="/run/user/$(id -u)"'
if ! in_container && [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$(id -u)" ]; then
    for rc in ~/.bashrc ~/.zshrc ~/.profile; do
        if [ -f "$rc" ] && ! grep -q 'XDG_RUNTIME_DIR' "$rc"; then
            echo "$XDG_LINE" >> "$rc"
            echo "Added XDG_RUNTIME_DIR to $rc"
        fi
    done
fi

# Global npm packages (ccstatusline, ...) of a Node installed above land in
# ~/.local/node/bin: put it on PATH for new shells too.
if [ -x "$NODE_HOME/bin/npm" ]; then
    NODE_PATH_LINE='case ":$PATH:" in *":$HOME/.local/node/bin:"*) ;; *) export PATH="$HOME/.local/node/bin:$PATH" ;; esac'
    for rc in ~/.bashrc ~/.zshrc ~/.profile; do
        if [ -f "$rc" ] && ! grep -qF "$NODE_PATH_LINE" "$rc"; then
            echo "$NODE_PATH_LINE" >> "$rc"
            echo "Added ~/.local/node/bin to PATH in $rc"
        fi
    done
fi

# --- 3. Script Setup & Statusline Configuration ---
# Command files reference this repo's own docs through the __DOTFILES_DIR__
# placeholder, resolved here to wherever this checkout actually lives
# (~/dotfiles on a bare host, the bind-mount target in a devcontainer, ...),
# so no user name or home directory is hardcoded in the repo.
# Commands removed from this repo are listed in RETIRED_COMMANDS and deleted
# from every account; any other file in the commands directory is the user's
# own and is left alone.
RETIRED_COMMANDS="show-prompt-setup-env.md"
install_commands() {
    local dest="$1" f
    mkdir -p "$dest"
    for f in "$DOTFILES_DIR/claude/commands/"*.md; do
        sed "s|__DOTFILES_DIR__|$DOTFILES_DIR|g" "$f" > "$dest/$(basename "$f")"
    done
    for f in $RETIRED_COMMANDS; do
        rm -f "$dest/$f"
    done
}

cp "$DOTFILES_DIR/claude/scripts/statusline-command.sh" "$TARGET_CLAUDE/scripts/"
cp "$DOTFILES_DIR/claude/scripts/statusline-wrapper.sh" "$TARGET_CLAUDE/scripts/"
cp "$DOTFILES_DIR/claude/scripts/subagent-statusline.sh" "$TARGET_CLAUDE/scripts/"
cp "$DOTFILES_DIR/claude/scripts/claude-accounts.sh" "$TARGET_CLAUDE/scripts/"
install_commands "$TARGET_CLAUDE/commands"
cp "$DOTFILES_DIR/ccstatusline/settings.json" ~/.config/ccstatusline/settings.json

# --- 3b. Propagate commands to every other Claude Code account ---
# Each alias in claude-accounts.sh points CLAUDE_CONFIG_DIR at its own
# directory, so commands copied only into $TARGET_CLAUDE (the default
# account) are invisible to every other account. Mirror the same discovery
# claude-accounts.sh uses -- global /tmp/.claude-accounts/* (falling back to
# ~/.claude-accounts on a bare host with no /tmp mount), plus per-project
# .devcontainer/.claude-* dirs -- and copy commands into each one too.
propagate_commands() {
    local acct_dir="$1"
    [ -d "$acct_dir" ] || return
    install_commands "$acct_dir/commands"
}

if in_container && [ -d /tmp/.claude-accounts ]; then
    CLAUDE_ACCOUNTS_GLOBAL_ROOT="/tmp/.claude-accounts"
else
    CLAUDE_ACCOUNTS_GLOBAL_ROOT="$HOME/.claude-accounts"
fi

if [ -d "$CLAUDE_ACCOUNTS_GLOBAL_ROOT" ]; then
    while IFS= read -r acct_dir; do
        propagate_commands "$acct_dir"
    done < <(find "$CLAUDE_ACCOUNTS_GLOBAL_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

for ws in /workspaces/*/; do
    if [ -d "${ws}.devcontainer" ]; then
        while IFS= read -r acct_dir; do
            [ "$(basename "$acct_dir")" = ".claude-backup" ] && continue
            propagate_commands "$acct_dir"
        done < <(find "${ws}.devcontainer" -maxdepth 1 -type d -name '.claude-*' 2>/dev/null)
    fi
done

chmod +x "$TARGET_CLAUDE/scripts/statusline-command.sh"
chmod +x "$TARGET_CLAUDE/scripts/statusline-wrapper.sh"
chmod +x "$TARGET_CLAUDE/scripts/subagent-statusline.sh"

if [ -f "$TARGET_CLAUDE/settings.json" ]; then
    if command -v jq &> /dev/null; then
        merged="$(mktemp "$TARGET_CLAUDE/.settings.json.XXXXXX")"
        if jq -s '.[0] * .[1]' "$TARGET_CLAUDE/settings.json" "$DOTFILES_DIR/claude/settings.json" > "$merged" \
            && mv "$merged" "$TARGET_CLAUDE/settings.json"; then
            :
        else
            rm -f "$merged"
            # Typically a settings.json owned by root, written by a container running as
            # real root on a rootful Docker engine.
            warn "statusLine/subagentStatusLine not merged into $TARGET_CLAUDE/settings.json (unreadable or invalid JSON; check its owner with ls -ln). Fix it and re-run install.sh."
        fi
    else
        warn "statusLine/subagentStatusLine not merged into $TARGET_CLAUDE/settings.json: merge them manually from $DOTFILES_DIR/claude/settings.json."
    fi
else
    cp "$DOTFILES_DIR/claude/settings.json" "$TARGET_CLAUDE/settings.json"
fi

if ! command -v ccstatusline &> /dev/null; then
    if command -v npm &> /dev/null; then
        npm_install_global ccstatusline
    fi
fi

# --- 4. Claude Code Account-Switching Aliases ---
# claude-<label> of the default account (once its email has a label) plus one alias per .devcontainer/.claude-<name>/
# directory the current workspace happens to have (see claude-accounts.sh for
# the discovery logic) -- portable across any devcontainer of this user.
#
# ~/.profile is included alongside ~/.bashrc/~/.zshrc because a login shell
# invoked as "sh" (e.g. the account's /etc/passwd shell is /bin/sh, even when
# /bin/sh resolves to bash) reads only /etc/profile and ~/.profile -- never
# ~/.bashrc or ~/.bash_profile -- so without this, account aliases silently
# don't exist in that login shell.
SOURCE_LINE="source \"$TARGET_CLAUDE/scripts/claude-accounts.sh\""
for rc in ~/.bashrc ~/.zshrc ~/.profile; do
    if [ -f "$rc" ] && ! grep -qF "$SOURCE_LINE" "$rc"; then
        echo "$SOURCE_LINE" >> "$rc"
        echo "Added to $rc: $SOURCE_LINE"
    fi
done

# A shell some terminal/IDE/exec mechanism spawns as "sh" without --login (so
# neither ~/.profile nor ~/.bashrc gets read) still honors $ENV, if already
# present in its inherited environment, as the file to source on startup.
# Export it from the two files a login shell of either name does read, so
# it's there in the environment by the time any such non-login child spawns.
ENV_LINE="export ENV=\"$TARGET_CLAUDE/scripts/claude-accounts.sh\""
for rc in ~/.bashrc ~/.profile; do
    if [ -f "$rc" ] && ! grep -qF "$ENV_LINE" "$rc"; then
        echo "$ENV_LINE" >> "$rc"
        echo "Added to $rc: $ENV_LINE"
    fi
done

if [ ${#WARNINGS[@]} -eq 0 ]; then
    echo "Dotfiles and Claude CLI installed successfully."
else
    printf '\n\033[01;33m[dotfiles] Installed with %d warning(s):\033[00m\n' "${#WARNINGS[@]}" >&2
    printf '\033[01;33m  - %s\033[00m\n' "${WARNINGS[@]}" >&2
fi
