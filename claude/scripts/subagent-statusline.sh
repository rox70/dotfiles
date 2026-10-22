#!/bin/bash
# subagentStatusLine: renders one line per row in the agent panel.
# Payload shape (undocumented, reverse-engineered): {"tasks":[{"id","status","label","model","tokenCount","contextWindowSize",...}, ...]}
# Each task carries its OWN model id (e.g. a subagent dispatched with a
# different model than the parent session) -- unlike the main statusLine
# payload, there is no top-level .model here, so falling back to the parent
# session's model (the earlier bug) means every row silently shows the same
# default model regardless of what that task is actually running.
input=$(cat)

if ! command -v jq > /dev/null 2>&1; then
  printf '\033[01;33m\xe2\x9a\xa0 jq missing: subagent statusline unavailable\033[00m\n'
  exit 0
fi

# claude-sonnet-5 -> "Sonnet 5", claude-haiku-4-5-20251001 -> "Haiku 4.5"
friendly_model() {
  local id="$1"
  id="${id#claude-}"
  local name version_parts=() part
  IFS='-' read -ra bits <<< "$id"
  for part in "${bits[@]}"; do
    if [ -z "$name" ] && [[ "$part" =~ ^[a-zA-Z]+$ ]]; then
      name="$part"
    elif [[ "$part" =~ ^[0-9]+$ ]] && [ "${#part}" -lt 6 ]; then
      version_parts+=("$part")
    fi
    # 8-digit date snapshot suffixes (e.g. 20251001) are dropped: not a version
  done
  if [ -n "$name" ]; then
    local cap="$(tr '[:lower:]' '[:upper:]' <<< "${name:0:1}")${name:1}"
    local IFS=.
    echo "${cap}${version_parts:+ ${version_parts[*]}}"
  else
    echo "$id"
  fi
}

status_color() {
  case "$1" in
    completed) echo '01;32' ;;
    failed|error) echo '01;31' ;;
    running|*) echo '01;36' ;;
  esac
}

count=$(echo "$input" | jq '.tasks | length' 2>/dev/null)
[ -z "$count" ] || [ "$count" -eq 0 ] 2>/dev/null && exit 0

for i in $(seq 0 $((count - 1))); do
  task=$(echo "$input" | jq -c ".tasks[$i]")
  label=$(echo "$task" | jq -r '.label // .description // "task"')
  model_id=$(echo "$task" | jq -r '.model // empty')
  status=$(echo "$task" | jq -r '.status // "running"')
  tokens=$(echo "$task" | jq -r '.tokenCount // 0')
  ctx=$(echo "$task" | jq -r '.contextWindowSize // 0')

  model_str=""
  if [ -n "$model_id" ]; then
    printf -v model_str ' \033[01;35m%s\033[00m' "$(friendly_model "$model_id")"
  fi

  pct_str=""
  if [ -n "$ctx" ] && [ "$ctx" -gt 0 ] 2>/dev/null; then
    pct=$(( tokens * 100 / ctx ))
    pct_str=" (${pct}%)"
  fi

  color=$(status_color "$status")
  printf "\033[${color}m%s\033[00m%s%s\n" "$label" "$model_str" "$pct_str"
done
