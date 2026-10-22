#!/usr/bin/env bash
# addon.sh — optional AI tooling, installed only on request (nothing is preinstalled).
#   addon.sh list                            add-ons, plugins and marketplaces: selection, where installed
#   addon.sh install <name|all> [alias...]   select a built-in add-on in addons.conf and install it
#   addon.sh plugin <name@mkt>... [alias...] select Claude Code plugins in addons.conf and install them
#   addon.sh marketplace <name> <source>     register a plugin marketplace in addons.conf and add it
#   addon.sh sync                            reinstall everything in addons.conf at the latest
#                                            version (run by the devcontainer post-create)
#
# Built-in add-ons (`all` = openspec speckit mattpocock superpowers):
#   openspec-cli  OpenSpec CLI (npm @fission-ai/openspec@latest), global in the container
#   openspec      openspec-cli + `openspec init --tools claude` in each child repo
#                 (`openspec update` when already initialised: skills follow the CLI)
#   speckit       GitHub Spec Kit (latest from git, via uv): `specify init` in each child repo;
#                 a re-run keeps .specify/memory/ (constitution)
#   mattpocock    plugin mattpocock-skills@claude-plugins-official
#   superpowers   plugin superpowers@claude-plugins-official
# Any other plugin: `plugin <name>@<marketplace>`. claude-plugins-official is known; register
# any other marketplace first with `marketplace <name> <source>` (git URL, owner/repo or path).
#
# The selection lives in addons.conf, one entry per line (no alias = every child repo):
#   <add-on> [<alias> ...]            plugin <name>@<marketplace> [<alias> ...]
#   marketplace <name> <source>
# Plugins are installed with project scope in the orchestrator root and in each selected
# child repo: their .claude/settings.json lives in overlay/<alias>/ (local only, never pushed),
# and worktrees see it through the overlay symlinks. Repo-level files created by `init`
# commands are adopted by the overlay at the end (`make overlay`).
# Managed by dotfiles/orchestrator: local edits are overwritten by `make update`.
set -euo pipefail
ORCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ORCH"

OFFICIAL_MKT="claude-plugins-official"
OFFICIAL_SRC="anthropics/claude-plugins-official"
SPECKIT_SRC="git+https://github.com/github/spec-kit.git"
CONF="addons.conf"

ADDONS="openspec-cli openspec speckit mattpocock superpowers"
ALL="openspec speckit mattpocock superpowers"

usage() { sed -n '3,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
die() { echo "error: $*" >&2; exit 1; }

# The post-create runs before dotfiles link ~/.claude to the shared login volume: point
# claude at the volume directly, or plugins would land in a container-local ~/.claude.
if [[ -d /tmp/.claude-host && ! -L "$HOME/.claude" && -z "${CLAUDE_CONFIG_DIR:-}" ]]; then
  export CLAUDE_CONFIG_DIR=/tmp/.claude-host
fi
export PATH="$HOME/.local/bin:$PATH"

# <alias> <folder> for every child repo, or only for the aliases given
repos() {
  local want=" $* "
  { grep -vE '^\s*(#|$)' repos.conf || true; } | while read -r alias dir _; do
    [[ $# -eq 0 || "$want" == *" $alias "* ]] && echo "$alias $dir"
  done
}
check_aliases() {
  local a
  for a in "$@"; do
    grep -qE "^\s*$a\s" repos.conf || die "unknown repo alias: $a (see repos.conf)"
  done
}
# A child repo whose .claude/ is versioned upstream must not get local settings in it
tracked_claude() { [[ -n "$(git -C "$1" ls-files -- .claude | head -1)" ]]; }
cloned() { [[ -d "$2/.git" ]] || { echo "[$1] skipped: $2 is not cloned (make bootstrap)"; return 1; }; }

# --- addons.conf ---------------------------------------------------------------------------
# Entry lines (no comments or blanks)
selected() { [[ -f "$CONF" ]] && { grep -vE '^\s*(#|$)' "$CONF" || true; }; }

# conf_set <key1> <key2|""> <line...>: replace the entry whose first field is key1 (and second
# field key2, when given) with <line>, or append it
conf_set() {
  local k1="$1" k2="$2" tmp; shift 2
  [[ -f "$CONF" ]] || printf '# Optional AI tooling of this orchestrator: see scripts/addon.sh\n' > "$CONF"
  tmp="$(mktemp)"
  awk -v k1="$k1" -v k2="$k2" '!($1 == k1 && (k2 == "" || $2 == k2))' "$CONF" > "$tmp"
  echo "$*" >> "$tmp"
  mv "$tmp" "$CONF"
}

# Aliases of an entry ("all repos" when none); <key1> <key2|"">
selection_of() {
  selected | awk -v k1="$1" -v k2="$2" '
    $1 == k1 && (k2 == "" || $2 == k2) {
      $1 = ""; if (k2 != "") $2 = ""; sub(/^ +/, ""); print ($0 == "" ? "all repos" : $0) }'
}

# --- plugins -------------------------------------------------------------------------------
plugin_of() {
  case "$1" in
    mattpocock)  echo "mattpocock-skills@$OFFICIAL_MKT" ;;
    superpowers) echo "superpowers@$OFFICIAL_MKT" ;;
  esac
}

# enabledPlugins of <dir>/.claude/settings.json contains <plugin>
has_plugin() {
  [[ -f "$1/.claude/settings.json" ]] && command -v jq > /dev/null \
    && jq -e --arg p "$2" '.enabledPlugins[$p] == true' "$1/.claude/settings.json" > /dev/null 2>&1
}

marketplace_source() { # <name>: the built-in source or the one registered in addons.conf
  [[ "$1" == "$OFFICIAL_MKT" ]] && { echo "$OFFICIAL_SRC"; return; }
  selected | awk -v n="$1" '$1 == "marketplace" && $2 == n { print $3; exit }'
}

known_marketplace() {
  claude plugin marketplace list 2>/dev/null | grep -qE "(^|[^[:alnum:]_-])$1([^[:alnum:]_-]|$)"
}

# Marketplaces already added/refreshed by this run (exported: sync runs add-ons as children)
export ADDON_MKT_FRESH="${ADDON_MKT_FRESH:-}"

# Explicit return codes, no `die`: sync calls it in a `||` context, where `set -e` is ignored
ensure_marketplace() { # <name>: add it, or refresh it to see new plugin versions
  local src
  command -v claude > /dev/null || { echo "error: claude CLI not found" >&2; return 1; }
  [[ " $ADDON_MKT_FRESH " == *" $1 "* ]] && return 0
  # A marketplace is only a catalog: adding it installs nothing
  if known_marketplace "$1"; then
    claude plugin marketplace update "$1" || return 1
  else
    src="$(marketplace_source "$1")"
    if [[ -z "$src" ]]; then
      echo "error: unknown marketplace: $1 (register it: make marketplace NAME=$1 URL=<source>)" >&2
      return 1
    fi
    claude plugin marketplace add "$src" || return 1
    if ! known_marketplace "$1"; then
      echo "error: $src was added but does not define a marketplace named $1 (see: claude plugin marketplace list)" >&2
      return 1
    fi
  fi
  ADDON_MKT_FRESH+=" $1"
}

plugin_in() { # <label> <dir> <plugin>: install, or update to the latest version
  local dir="$2"
  # Claude refuses to write settings into a symlinked .claude/ (a child repo's points to
  # overlay/<alias>/.claude): run it from the overlay folder that really holds the file.
  # The child repo and its worktrees read the same settings through the symlink.
  [[ -L "$dir/.claude" ]] && dir="$(dirname "$(readlink -f "$dir/.claude")")"
  if has_plugin "$dir" "$3"; then
    echo "[$1] update $3"
    (cd "$dir" && claude plugin update --scope project "$3")
  else
    echo "[$1] install $3"
    (cd "$dir" && claude plugin install --scope project "$3")
  fi
}

install_plugin() { # <name@marketplace> <alias...>
  local plugin="$1" alias dir; shift
  [[ "$plugin" == ?*@?* ]] || die "not a plugin id: $plugin (expected <name>@<marketplace>)"
  ensure_marketplace "${plugin#*@}"
  plugin_in orchestrator . "$plugin"
  while read -r alias dir; do
    cloned "$alias" "$dir" || continue
    if tracked_claude "$dir"; then echo "[$alias] skipped: .claude/ is versioned in the repo"; continue; fi
    plugin_in "$alias" "$dir" "$plugin"
  done < <(repos "$@")
}

# --- built-in add-ons ----------------------------------------------------------------------
install_openspec_cli() {
  command -v npm > /dev/null || die "npm not found (add the node Feature to the devcontainer)"
  npm i -g @fission-ai/openspec@latest
  echo "OpenSpec CLI $(openspec --version)"
}

install_openspec() { # <alias...>
  install_openspec_cli
  local alias dir
  while read -r alias dir; do
    cloned "$alias" "$dir" || continue
    # OpenSpec refuses to write through a symlinked .claude/ ("Path is outside the allowed
    # directory"): run it from the overlay folder that really holds .claude/ and openspec/.
    # The child repo and its worktrees see the result through the symlinks.
    [[ -L "$dir/.claude" ]] && dir="$(dirname "$(readlink -f "$dir/.claude")")"
    if [[ -d "$dir/openspec" ]]; then
      echo "[$alias] openspec update"
      (cd "$dir" && openspec update)
    else
      echo "[$alias] openspec init"
      (cd "$dir" && openspec init --tools claude --no-copilot-cloud --no-animation)
    fi
  done < <(repos "$@")
}

install_speckit() { # <alias...>
  if ! command -v uvx > /dev/null; then
    echo "uv not found: installing it into ~/.local/bin (https://astral.sh/uv)"
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
  # Spec Kit keeps its files in .specify/: make sure the overlay adopts them
  grep -qE '^\*\s+\.specify$' overlay/manifest || printf '*  .specify\n' >> overlay/manifest
  local alias dir keep
  while read -r alias dir; do
    cloned "$alias" "$dir" || continue
    echo "[$alias] specify init"
    # --force refreshes the templates; .specify/memory/ holds the project's own constitution
    keep=""
    if [[ -d "$dir/.specify/memory" ]]; then keep="$(mktemp -d)"; cp -a "$dir/.specify/memory/." "$keep/"; fi
    (cd "$dir" && uvx --refresh --from "$SPECKIT_SRC" specify init --here --ai claude --script sh --no-git --force)
    if [[ -n "$keep" ]]; then cp -a "$keep/." "$dir/.specify/memory/"; rm -rf "$keep"; fi
  done < <(repos "$@")
}

unknown_addon() {
  case "$1" in
    ddi) die "the ddi add-on was removed: register its marketplace (make marketplace NAME=... URL=...) and pick plugins (make plugin P=\"<name>@<marketplace> ...\")" ;;
    *)   die "unknown add-on: $1 (one of: $ADDONS, all; any plugin: make plugin P=<name>@<marketplace>)" ;;
  esac
}

# One addons.conf entry: <add-on> [alias...] | plugin <id> [alias...] | marketplace <name> <src>
install_one() {
  local addon="$1"; shift
  case "$addon" in
    openspec-cli)            install_openspec_cli ;;
    openspec)                install_openspec "$@" ;;
    speckit)                 install_speckit "$@" ;;
    mattpocock|superpowers)  install_plugin "$(plugin_of "$addon")" "$@" ;;
    plugin)                  install_plugin "$@" ;;
    marketplace)             ensure_marketplace "$1" ;;
    *)                       unknown_addon "$addon" ;;
  esac
}

# --- commands ------------------------------------------------------------------------------
sync() {
  local line failed=() n=0
  # Marketplaces first: their plugins need the refreshed catalogs
  while read -r line; do
    n=$((n + 1))
    # shellcheck disable=SC2086
    set -- $line
    echo "== ${*:1:2}"
    if [[ "$1" == marketplace ]]; then
      # In this shell, not a child: ADDON_MKT_FRESH must record the refresh for the plugins
      ensure_marketplace "$2" || failed+=("marketplace $2")
    else
      # A separate process, not a subshell: `set -e` is ignored inside `( ... ) || ...`, so a
      # failed step would not stop the add-on nor mark it as failed
      "${BASH_SOURCE[0]}" _install-one "$@" || failed+=("${*:1:2}")
    fi
  done < <(selected | awk '$1 == "marketplace"'; selected | awk '$1 != "marketplace"')
  [[ $n -gt 0 ]] || { echo "nothing selected in $CONF"; return 0; }
  ./scripts/overlay.sh link
  if [[ ${#failed[@]} -gt 0 ]]; then
    echo "failed: $(printf '%s, ' "${failed[@]}" | sed 's/, $//') (re-run: make addons-sync)" >&2
    return 1
  fi
}

# Where <plugin> is enabled: orchestrator and/or child repo aliases
plugin_where() {
  local where="" alias dir
  has_plugin . "$1" && where="orchestrator "
  while read -r alias dir; do
    has_plugin "$dir" "$1" && where+="$alias "
  done < <(repos)
  echo "${where:--}"
}

list() {
  local addon alias dir where sel plugin
  printf '%-40s %-14s %s\n' "ADD-ON" "SELECTED" "INSTALLED IN"
  for addon in $ADDONS; do
    where=""
    sel="$(selection_of "$addon" "")"
    case "$addon" in
      openspec-cli)
        command -v openspec > /dev/null && where="container ($(openspec --version 2>/dev/null))" ;;
      openspec|speckit)
        while read -r alias dir; do
          if [[ "$addon" == openspec && -d "$dir/openspec" ]] || [[ "$addon" == speckit && -d "$dir/.specify" ]]; then
            where+="$alias "
          fi
        done < <(repos) ;;
      *) where="$(plugin_where "$(plugin_of "$addon")")" ;;
    esac
    printf '%-40s %-14s %s\n' "$addon" "${sel:--}" "${where:--}"
  done
  while read -r plugin; do
    printf '%-40s %-14s %s\n' "plugin $plugin" "$(selection_of plugin "$plugin")" "$(plugin_where "$plugin")"
  done < <(selected | awk '$1 == "plugin" { print $2 }')
  selected | awk '$1 == "marketplace" { printf "%-40s %s\n", "marketplace " $2, $3 }'
  echo
  echo "Select + install: make addon-<name> | make addon-all [REPOS=\"<alias> ...\"]"
  echo "Other plugins:    make marketplace NAME=<name> URL=<source>; make plugin P=\"<name>@<marketplace> ...\" [REPOS=...]"
  echo "Reinstall the selection at the latest versions: make addons-sync (also on every rebuild)"
}

case "${1:-list}" in
  list) list ;;
  sync) sync ;;
  _install-one) shift; install_one "$@" ;;  # internal: used by sync
  install)
    addon="${2:-}"; [[ -n "$addon" ]] || usage 1
    shift 2
    check_aliases "$@"
    if [[ "$addon" == all ]]; then names="$ALL"; else names="$addon"; fi
    for a in $names; do
      [[ " $ADDONS " == *" $a "* ]] || unknown_addon "$a"
      echo "== $a"
      install_one "$a" "$@"
      # Recorded only once installed: a failed install is not retried on every rebuild
      conf_set "$a" "" "$a" "$@"
    done
    # Adopt the AI files the install created in the child repos, relink everywhere
    [[ "$names" == openspec-cli ]] || ./scripts/overlay.sh link
    ;;
  plugin)
    shift
    plugins=(); aliases=()
    for arg in "$@"; do
      if [[ "$arg" == *@* ]]; then plugins+=("$arg"); else aliases+=("$arg"); fi
    done
    [[ ${#plugins[@]} -gt 0 ]] || die "no plugin given (make plugin P=\"<name>@<marketplace> ...\" [REPOS=...])"
    check_aliases "${aliases[@]}"
    for p in "${plugins[@]}"; do
      [[ "$p" == ?*@?* ]] || die "not a plugin id: $p (expected <name>@<marketplace>)"
      echo "== plugin $p"
      install_plugin "$p" "${aliases[@]}"
      conf_set plugin "$p" plugin "$p" "${aliases[@]}"
    done
    ./scripts/overlay.sh link
    ;;
  marketplace)
    [[ $# -eq 3 ]] || die "usage: make marketplace NAME=<name> URL=<git URL | owner/repo | path>"
    [[ "$2" != "$OFFICIAL_MKT" ]] || die "$OFFICIAL_MKT is built in"
    # ensure_marketplace reads the source from addons.conf: record it, roll back on failure
    backup="$(mktemp)"; [[ -f "$CONF" ]] && cp "$CONF" "$backup"
    conf_set marketplace "$2" marketplace "$2" "$3"
    if ! ensure_marketplace "$2"; then
      if [[ -s "$backup" ]]; then mv "$backup" "$CONF"; else rm -f "$CONF" "$backup"; fi
      die "marketplace $2 not added: addons.conf left unchanged"
    fi
    rm -f "$backup"
    ;;
  -h|--help) usage ;;
  *) usage 1 ;;
esac
