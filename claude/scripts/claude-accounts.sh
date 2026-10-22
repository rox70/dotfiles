# Claude Code account-switching aliases. Portable across any devcontainer of
# this user (sourced from .bashrc/.zshrc by install.sh below) — no project-
# specific paths hardcoded here.
#
# The default account (no CLAUDE_CONFIG_DIR override, i.e. plain ~/.claude,
# itself shared cross-project via the /tmp/.claude-host symlink install.sh
# sets up) gets a claude-<label> alias when its login email has a label in
# ~/.claude/account-labels (see claude_account_label below).
#
# Any other alias comes from two sources, in this order (later wins on a
# name collision):
#   1. Per-project accounts: .devcontainer/.claude-<name>/ directories under
#      the current devcontainer's workspace root -- a project opts a
#      personal account IN just by creating that directory, no config here.
#      A directory literally named .devcontainer/.claude-backup is skipped
#      (reserved for backups, never an account).
#   2. Global accounts, shared across every devcontainer of this user that
#      bind-mounts the same host directory at /tmp/.claude-accounts (one
#      subdirectory per account, e.g. /tmp/.claude-accounts/work) --
#      logging in once under claude-work in any such project makes that
#      session available in all of them. Wins over a same-named per-project
#      account since a shared identity is the more specific intent once it
#      exists. On a bare (non-container) host ~/.claude-accounts is used
#      instead, never /tmp (shared by every user of the machine).

_claude_accounts_workspace_root() {
  local d
  # zsh aborts on a glob with no match ("no matches found"); make it expand to nothing
  [ -n "${ZSH_VERSION:-}" ] && setopt localoptions nullglob
  # VS Code's own bind-mount convention (workspaceFolder: /workspaces/<repo>).
  for d in /workspaces/*/; do
    [ -d "${d}.devcontainer" ] && { printf '%s' "${d%/}"; return; }
  done
  # Devcontainers that mirror the host path instead (workspaceFolder:
  # "${localWorkspaceFolder}") don't live under /workspaces at all -- walk up
  # from the shell's starting directory (workspaceFolder, for a VS Code
  # integrated terminal) looking for .devcontainer.
  d="$PWD"
  while [ "$d" != "/" ]; do
    [ -d "$d/.devcontainer" ] && { printf '%s' "$d"; return; }
    d="$(dirname "$d")"
  done
}

# Process substitution (`< <(...)`) is a bash/zsh-only extension -- a plain
# POSIX sh (dash, ash/busybox, ...) rejects it with a syntax error at source
# time, before any alias is defined. Capture `find` output into a variable
# with command substitution instead (which does NOT run the rest of the loop
# in a subshell, unlike piping into `while read`) and split it on newlines
# with a for loop, so this works whether this file is sourced by bash, zsh,
# or a real POSIX sh.
_claude_accounts_ws="$(_claude_accounts_workspace_root)"
if [ -n "$_claude_accounts_ws" ]; then
  _claude_accounts_dirs="$(find "$_claude_accounts_ws/.devcontainer" -maxdepth 1 -type d -name '.claude-*' 2>/dev/null)"
  if [ -n "$_claude_accounts_dirs" ]; then
    _claude_accounts_oldifs="$IFS"
    IFS='
'
    for _claude_accounts_dir in $_claude_accounts_dirs; do
      _claude_accounts_name="$(basename "$_claude_accounts_dir")"
      _claude_accounts_name="${_claude_accounts_name#.claude-}"
      [ "$_claude_accounts_name" = "backup" ] && continue
      alias "claude-${_claude_accounts_name}"="CLAUDE_CONFIG_DIR=\"${_claude_accounts_dir}\" claude"
    done
    IFS="$_claude_accounts_oldifs"
  fi
  unset _claude_accounts_dirs _claude_accounts_dir _claude_accounts_name _claude_accounts_oldifs
fi
unset _claude_accounts_ws

# /tmp only inside a container: on a host /tmp is shared by every user, and
# a /tmp/.claude-accounts created by someone else must never be trusted.
_claude_accounts_global_root_for() {
  if { [ -f /.dockerenv ] || [ -f /run/.containerenv ]; } && [ -d /tmp/.claude-accounts ]; then
    printf '%s' /tmp/.claude-accounts
  else
    printf '%s' "$HOME/.claude-accounts"
  fi
}
_claude_accounts_global_root="$(_claude_accounts_global_root_for)"

if [ -d "$_claude_accounts_global_root" ]; then
  _claude_accounts_dirs="$(find "$_claude_accounts_global_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)"
  if [ -n "$_claude_accounts_dirs" ]; then
    _claude_accounts_oldifs="$IFS"
    IFS='
'
    for _claude_accounts_dir in $_claude_accounts_dirs; do
      _claude_accounts_name="$(basename "$_claude_accounts_dir")"
      alias "claude-${_claude_accounts_name}"="CLAUDE_CONFIG_DIR=\"${_claude_accounts_dir}\" claude"
    done
    IFS="$_claude_accounts_oldifs"
  fi
  unset _claude_accounts_dirs _claude_accounts_dir _claude_accounts_name _claude_accounts_oldifs
fi
unset _claude_accounts_global_root

# Email -> label map used by the statusline: one "<email> <label>" line per
# account, next to the login (in a container: the shared claude-host volume),
# never in this repo. Whatever account you log in with, the statusline shows
# the label registered for its email. An email it has never seen is added
# automatically with an empty label (a bare "<email>" line), shown as the
# email until claude_account_label (or /account-label in Claude Code) sets one.
CLAUDE_ACCOUNT_LABELS="$HOME/.claude/account-labels"

# _claude_accounts_default_label: the label registered for the email the
# default profile (~/.claude) is logged in with; empty when it has no login,
# no label, or jq is missing. This is what makes claude-<label> mean "the
# default profile" -- no separate setting to keep in sync.
_claude_accounts_default_label() {
  command -v jq > /dev/null 2>&1 && [ -r "$HOME/.claude.json" ] && [ -r "$CLAUDE_ACCOUNT_LABELS" ] || return 0
  _claude_default_email=$(jq -r '.oauthAccount.emailAddress // empty' "$HOME/.claude.json" 2>/dev/null)
  [ -n "$_claude_default_email" ] && awk -v e="$_claude_default_email" \
    'tolower($1) == tolower(e) { print $2; exit }' "$CLAUDE_ACCOUNT_LABELS"
  unset _claude_default_email
}

# claude_account_label <label> [email]: register (or replace) the label shown
# in the statusline for <email>, by default the email of the account currently
# logged in (CLAUDE_CONFIG_DIR, else the default ~/.claude). Works for any
# account, the default one too. Same as /account-label inside Claude Code.
claude_account_label() {
  _claude_accounts_email="$2"
  if [ -z "$_claude_accounts_email" ]; then
    case "${CLAUDE_CONFIG_DIR:-}" in
      ''|"$HOME/.claude"|"$HOME/.claude/") _claude_accounts_config="$HOME/.claude.json" ;;
      *) _claude_accounts_config="${CLAUDE_CONFIG_DIR%/}/.claude.json" ;;
    esac
    command -v jq > /dev/null 2>&1 && [ -r "$_claude_accounts_config" ] \
      && _claude_accounts_email=$(jq -r '.oauthAccount.emailAddress // empty' "$_claude_accounts_config" 2>/dev/null)
    unset _claude_accounts_config
  fi
  case "$1" in
    ''|*[!A-Za-z0-9._@-]*)
      echo "usage: claude_account_label <label> [email]  (label: letters, digits, . _ @ -)" >&2
      unset _claude_accounts_email
      return 1 ;;
  esac
  if [ -z "$_claude_accounts_email" ]; then
    echo "claude_account_label: no logged-in account found, pass the email explicitly" >&2
    return 1
  fi
  touch "$CLAUDE_ACCOUNT_LABELS" || { unset _claude_accounts_email; return 1; }
  awk -v e="$_claude_accounts_email" 'tolower($1) != tolower(e)' "$CLAUDE_ACCOUNT_LABELS" > "$CLAUDE_ACCOUNT_LABELS.tmp" \
    && printf '%s %s\n' "$_claude_accounts_email" "$1" >> "$CLAUDE_ACCOUNT_LABELS.tmp" \
    && mv "$CLAUDE_ACCOUNT_LABELS.tmp" "$CLAUDE_ACCOUNT_LABELS" || { unset _claude_accounts_email; return 1; }
  echo "Statusline label for $_claude_accounts_email: $1"
  unset _claude_accounts_email
}

# claude_account_rename <old> <new>: rename the label <old> to <new>, whatever
# account it belongs to. An extra profile directory named <old> is renamed too,
# so claude-<new> keeps matching it (quit any Claude session running in that
# profile first). Same as /account-label <old> <new> inside Claude Code.
claude_account_rename() {
  case "$1" in
    ''|*[!A-Za-z0-9._@-]*) echo "usage: claude_account_rename <old-label> <new-label>" >&2; return 1 ;;
  esac
  case "$2" in
    ''|*[!A-Za-z0-9._@-]*) echo "usage: claude_account_rename <old-label> <new-label>  (label: letters, digits, . _ @ -)" >&2; return 1 ;;
  esac
  [ "$1" = "$2" ] && { echo "claude_account_rename: old and new label are the same" >&2; return 1; }
  if ! awk -v o="$1" '$2 == o { f = 1 } END { exit !f }' "$CLAUDE_ACCOUNT_LABELS" 2>/dev/null; then
    echo "claude_account_rename: no account labelled \"$1\" (see claude_account_list)" >&2
    return 1
  fi
  if awk -v n="$2" '$2 == n { f = 1 } END { exit !f }' "$CLAUDE_ACCOUNT_LABELS"; then
    echo "claude_account_rename: label \"$2\" is already used (see claude_account_list)" >&2
    return 1
  fi
  _claude_rename_root="$(_claude_accounts_global_root_for)"
  if [ -d "$_claude_rename_root/$1" ]; then
    if [ -e "$_claude_rename_root/$2" ]; then
      echo "claude_account_rename: $_claude_rename_root/$2 already exists" >&2
      unset _claude_rename_root
      return 1
    fi
    mv "$_claude_rename_root/$1" "$_claude_rename_root/$2" || { unset _claude_rename_root; return 1; }
    unalias "claude-$1" 2> /dev/null
    alias "claude-$2"="CLAUDE_CONFIG_DIR=\"$_claude_rename_root/$2\" claude"
    echo "Profile directory renamed: $_claude_rename_root/$2 (use claude-$2)"
  else
    unalias "claude-$1" 2> /dev/null
    [ "$1" = "$(_claude_accounts_default_label)" ] && alias "claude-$2"="claude_account_start $2"
  fi
  awk -v o="$1" -v n="$2" '$2 == o { $2 = n } { print }' "$CLAUDE_ACCOUNT_LABELS" > "$CLAUDE_ACCOUNT_LABELS.tmp" \
    && mv "$CLAUDE_ACCOUNT_LABELS.tmp" "$CLAUDE_ACCOUNT_LABELS" || { unset _claude_rename_root; return 1; }
  echo "Label renamed: $1 -> $2"
  unset _claude_rename_root
}

# claude_account_list: show every registered email and its label
# ("(no label)" for accounts added automatically by the statusline).
claude_account_list() {
  [ -s "$CLAUDE_ACCOUNT_LABELS" ] || { echo "No accounts registered yet."; return 0; }
  awk '{ printf "%-40s %s\n", $1, ($2 == "" ? "(no label)" : $2) }' "$CLAUDE_ACCOUNT_LABELS"
}

# claude_account_add [label] [email]: create a new global account directory
# and its claude-<label> alias in the current shell (other shells pick it up
# at startup). The label is prompted for when missing; the email is optional:
# without it, the statusline registers the email of the first login made in
# that directory under <label>. Then run claude-<label> once to log in.
# Underscore name, not hyphen: a real POSIX sh rejects hyphens in function names.
claude_account_add() {
  _claude_accounts_label="$1"
  _claude_accounts_email="$2"
  if [ -z "$_claude_accounts_label" ]; then
    printf 'Label (alias claude-<label>): '
    read -r _claude_accounts_label
  fi
  case "$_claude_accounts_label" in
    ''|*[!A-Za-z0-9._-]*)
      echo "claude_account_add: label must be non-empty and use only letters, digits, . _ -" >&2
      unset _claude_accounts_label _claude_accounts_email
      return 1 ;;
  esac
  case "$_claude_accounts_email" in
    ''|*@*) ;;
    *)
      echo "claude_account_add: '$_claude_accounts_email' is not an email" >&2
      unset _claude_accounts_label _claude_accounts_email
      return 1 ;;
  esac
  _claude_accounts_root="$(_claude_accounts_global_root_for)"
  mkdir -p "$_claude_accounts_root/$_claude_accounts_label" || return 1
  if [ -d "$HOME/.claude/commands" ]; then
    mkdir -p "$_claude_accounts_root/$_claude_accounts_label/commands"
    cp -R "$HOME/.claude/commands/." "$_claude_accounts_root/$_claude_accounts_label/commands/"
  fi
  alias "claude-$_claude_accounts_label"="CLAUDE_CONFIG_DIR=\"$_claude_accounts_root/$_claude_accounts_label\" claude"
  [ -n "$_claude_accounts_email" ] && claude_account_label "$_claude_accounts_label" "$_claude_accounts_email"
  echo "Added claude-$_claude_accounts_label -> $_claude_accounts_root/$_claude_accounts_label (run claude-$_claude_accounts_label once to log in${_claude_accounts_email:+ as $_claude_accounts_email})."
  unset _claude_accounts_root _claude_accounts_label _claude_accounts_email
}

# _claude_accounts_logged_in [config-dir]: true when that profile (default:
# the default ~/.claude one) has a login.
_claude_accounts_logged_in() {
  if [ -n "$1" ]; then
    CLAUDE_CONFIG_DIR="$1" command claude auth status > /dev/null 2>&1
  else
    env -u CLAUDE_CONFIG_DIR claude auth status > /dev/null 2>&1
  fi
}

# _claude_accounts_login <label> <config-dir|""> [email]: log that profile in
# (pre-filling <email> when given), then register the email actually used
# under <label> for the statusline, warning when it differs from <email>.
_claude_accounts_login() {
  if [ -n "$2" ]; then
    CLAUDE_CONFIG_DIR="$2" command claude auth login ${3:+--email "$3"} || return 1
    _claude_login_email=$(CLAUDE_CONFIG_DIR="$2" command claude auth status --json 2>/dev/null \
      | jq -r '.email // empty' 2>/dev/null)
  else
    env -u CLAUDE_CONFIG_DIR claude auth login ${3:+--email "$3"} || return 1
    _claude_login_email=$(env -u CLAUDE_CONFIG_DIR claude auth status --json 2>/dev/null \
      | jq -r '.email // empty' 2>/dev/null)
  fi
  if [ -n "$_claude_login_email" ]; then
    if [ -n "$3" ] && [ "$(printf '%s' "$3" | tr 'A-Z' 'a-z')" != "$(printf '%s' "$_claude_login_email" | tr 'A-Z' 'a-z')" ]; then
      echo "Note: logged in as $_claude_login_email, not $3." >&2
    fi
    # Labels are per email: the same email in two profiles can keep only one
    _claude_login_prev=$(awk -v e="$_claude_login_email" 'tolower($1) == tolower(e) { print $2; exit }' \
      "$CLAUDE_ACCOUNT_LABELS" 2>/dev/null)
    if [ -n "$_claude_login_prev" ] && [ "$_claude_login_prev" != "$1" ]; then
      echo "Note: $_claude_login_email was labelled \"$_claude_login_prev\", now \"$1\" (labels are per email)." >&2
    fi
    unset _claude_login_prev
    claude_account_label "$1" "$_claude_login_email" > /dev/null
  fi
  unset _claude_login_email
}

# _claude_accounts_confirm <question>: ask [Y/n] on a terminal (Enter = yes);
# without a terminal the answer is always no, so nothing is created unattended.
_claude_accounts_confirm() {
  [ -t 0 ] || return 1
  printf '%s [Y/n] ' "$1" >&2
  read -r _claude_answer
  case "$_claude_answer" in
    ''|[Yy]*) unset _claude_answer; return 0 ;;
    *) unset _claude_answer; return 1 ;;
  esac
}

# claude_account_start <label> [email] [claude args...]: what claude-<label>
# runs (its alias, or the unknown-command hook below when no alias exists yet).
#   - <label> is the default profile's label (the label of the email it is
#     logged in with, see claude_account_label): start the default profile.
#   - <label> is an existing extra profile: start it.
#   - nothing exists yet (the default profile has no login): create the default
#     profile, log it in, register its email under <label>, start it. From
#     then on both claude and claude-<label> start it.
#   - otherwise: create the extra profile <label>, log it in, start it.
# When a profile is created or logged in here, an [email] given as first
# argument pre-fills the login page, and the email actually used is registered
# under <label> for the statusline. Plain claude never goes through here: with
# nothing set up it just asks for a login and stays unlabelled.
claude_account_start() {
  _claude_start_label="$1"
  shift
  _claude_start_email=""
  case "${1:-}" in
    -*) ;;
    *@*) _claude_start_email="$1"; shift ;;
  esac
  case "$_claude_start_label" in
    ''|*[!A-Za-z0-9._-]*)
      echo "claude_account_start: label must be non-empty and use only letters, digits, . _ -" >&2
      unset _claude_start_label _claude_start_email
      return 1 ;;
  esac
  _claude_start_dir="$(_claude_accounts_global_root_for)/$_claude_start_label"
  _claude_start_rc=0
  if [ "$_claude_start_label" = "$(_claude_accounts_default_label)" ]; then
    # Default profile
    env -u CLAUDE_CONFIG_DIR claude "$@"
    _claude_start_rc=$?
  elif [ -d "$_claude_start_dir" ]; then
    # Existing extra profile
    if [ -n "$_claude_start_email" ] && ! _claude_accounts_logged_in "$_claude_start_dir"; then
      _claude_accounts_login "$_claude_start_label" "$_claude_start_dir" "$_claude_start_email" || _claude_start_rc=1
    fi
    [ "$_claude_start_rc" -eq 0 ] && { CLAUDE_CONFIG_DIR="$_claude_start_dir" command claude "$@"; _claude_start_rc=$?; }
  elif ! _claude_accounts_logged_in; then
    # Nothing set up yet: this becomes the default profile
    if _claude_accounts_confirm "No Claude profile yet: create the default one, labelled \"$_claude_start_label\", and log in${_claude_start_email:+ as $_claude_start_email}?"; then
      _claude_accounts_login "$_claude_start_label" "" "$_claude_start_email" \
        && alias "claude-$_claude_start_label"="claude_account_start $_claude_start_label" \
        && { env -u CLAUDE_CONFIG_DIR claude "$@"; }
      _claude_start_rc=$?
    else
      _claude_start_rc=127
    fi
  elif _claude_accounts_confirm "Claude profile \"$_claude_start_label\" does not exist. Create it and log in${_claude_start_email:+ as $_claude_start_email}?"; then
    # New extra profile
    claude_account_add "$_claude_start_label" > /dev/null \
      && _claude_accounts_login "$_claude_start_label" "$_claude_start_dir" "$_claude_start_email" \
      && { CLAUDE_CONFIG_DIR="$_claude_start_dir" command claude "$@"; }
    _claude_start_rc=$?
  else
    _claude_start_rc=127
  fi
  unset _claude_start_label _claude_start_email _claude_start_dir
  return $_claude_start_rc
}

# claude-<label> with no alias yet (bash/zsh only, a POSIX sh has no hook for
# unknown commands): hand it to claude_account_start. Any handler already
# defined (e.g. the distro's command-not-found) still runs for every other
# unknown command, and for a declined creation.
_claude_accounts_cnf() {
  case "$1" in
    claude-?*) ;;
    *) return 127 ;;
  esac
  case "${1#claude-}" in
    *[!A-Za-z0-9._-]*) return 127 ;;
  esac
  _claude_cnf_label="${1#claude-}"
  shift
  claude_account_start "$_claude_cnf_label" "$@"
  _claude_cnf_rc=$?
  unset _claude_cnf_label
  return $_claude_cnf_rc
}

# Default profile alias (defined last: it wins over a same-named extra one,
# matching claude_account_start, which checks the default first)
_claude_accounts_name="$(_claude_accounts_default_label)"
[ -n "$_claude_accounts_name" ] && alias "claude-$_claude_accounts_name"="claude_account_start $_claude_accounts_name"
unset _claude_accounts_name

if [ -n "${BASH_VERSION:-}" ]; then
  # Keep a pre-existing handler (renamed once; re-sourcing must not wrap ourselves)
  if declare -f command_not_found_handle > /dev/null 2>&1 \
     && ! declare -f _claude_accounts_prev_cnf > /dev/null 2>&1; then
    eval "_claude_accounts_prev_cnf$(declare -f command_not_found_handle | sed '1s/^command_not_found_handle//')"
  fi
  command_not_found_handle() {
    _claude_accounts_cnf "$@"
    _claude_cnf_rc=$?
    [ "$_claude_cnf_rc" -ne 127 ] && return "$_claude_cnf_rc"
    if declare -f _claude_accounts_prev_cnf > /dev/null 2>&1; then
      _claude_accounts_prev_cnf "$@"
      return $?
    fi
    printf 'bash: %s: command not found\n' "$1" >&2
    return 127
  }
elif [ -n "${ZSH_VERSION:-}" ]; then
  if (( ${+functions[command_not_found_handler]} )) && ! (( ${+functions[_claude_accounts_prev_cnf]} )); then
    functions[_claude_accounts_prev_cnf]="${functions[command_not_found_handler]}"
  fi
  command_not_found_handler() {
    _claude_accounts_cnf "$@"
    _claude_cnf_rc=$?
    [ "$_claude_cnf_rc" -ne 127 ] && return "$_claude_cnf_rc"
    if (( ${+functions[_claude_accounts_prev_cnf]} )); then
      _claude_accounts_prev_cnf "$@"
      return $?
    fi
    printf 'zsh: command not found: %s\n' "$1" >&2
    return 127
  }
fi
