#!/bin/bash
input=$(cat)

# Personal settings (STATUSLINE_TZ): see install.sh
[ -f "$HOME/.claude/dotfiles.conf" ] && . "$HOME/.claude/dotfiles.conf"

# Account label (CLAUDE_CONFIG_DIR is set by the claude-* aliases in scripts/claude-accounts.sh;
# unset means the default config dir, labelled "default" until its email has a label)
if [ -z "${CLAUDE_CONFIG_DIR:-}" ] || [ "${CLAUDE_CONFIG_DIR%/}" = "$HOME/.claude" ]; then
  account_raw="default"
  account_config="$HOME/.claude.json"
  account_extra=""
else
  account_raw=$(basename "$CLAUDE_CONFIG_DIR")
  account_config="${CLAUDE_CONFIG_DIR%/}/.claude.json"
  account_extra=1
fi
account_raw="${account_raw#.}"

# Logged-in email -> label registered in ~/.claude/account-labels (claude_account_add /
# claude_account_label, /account-label). An email seen for the first time is registered
# automatically: in an extra account (claude-<label>) under that account's label, so an
# account created without email is completed by its first login; in the default account
# with an empty label, shown as the email itself.
# Not logged in or no jq: the label above.
account_email=""
command -v jq > /dev/null 2>&1 && [ -r "$account_config" ] \
  && account_email=$(jq -r '.oauthAccount.emailAddress // empty' "$account_config" 2>/dev/null)
account_label="\033[01;34m${account_raw}\033[00m"
if [ -n "$account_email" ]; then
  labels_file="$HOME/.claude/account-labels"
  entry=""
  [ -r "$labels_file" ] && entry=$(awk -v e="$account_email" \
    'tolower($1) == tolower(e) { print "found " $2; exit }' "$labels_file")
  if [ -z "$entry" ]; then
    printf '%s%s\n' "$account_email" "${account_extra:+ $account_raw}" >> "$labels_file" 2>/dev/null
    entry="found ${account_extra:+$account_raw}"
  fi
  mapped="${entry#found }"
  account_label="\033[01;34m${mapped:-$account_email}\033[00m"
fi

# Git info
git_info=$(echo "$input" | bash ~/.claude/scripts/statusline-command.sh)

# Everything below parses the JSON payload with jq: without it, say so
# instead of silently dropping model, usage and context.
if ! command -v jq > /dev/null 2>&1; then
  printf "%b" "${account_label} | \033[01;33m\xe2\x9a\xa0 jq missing\033[00m | ${git_info}"
  exit 0
fi

# Modello LLM in uso in questo istante
model_name=$(echo "$input" | jq -r '.model.display_name // .model.id // empty')
model_str=""
[ -n "$model_name" ] && model_str="\033[01;35m${model_name}\033[00m"

# Rate limits (solo se presenti - richiede piano Pro/Max e almeno 1 risposta API nella sessione)
five_h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Reset times in STATUSLINE_TZ (e.g. Europe/London), else the machine's local time zone
tz_date() { if [ -n "${STATUSLINE_TZ:-}" ]; then TZ="$STATUSLINE_TZ" date "$@"; else date "$@"; fi; }
five_h_reset_fmt=""
[ -n "$five_h_reset" ] && five_h_reset_fmt=$(tz_date -d "@$five_h_reset" '+%d/%m %H:%M' 2>/dev/null)
week_reset_fmt=""
[ -n "$week_reset" ] && week_reset_fmt=$(LC_TIME=C tz_date -d "@$week_reset" '+%a %d/%m %H:%M' 2>/dev/null)

# Colore in base alla percentuale di utilizzo: <=29 verde, 30-59 azzurro, 60-84 arancio, >=85 rosso
usage_color() {
  local pct=${1%.*}
  if [ "$pct" -le 29 ]; then
    echo '01;32'
  elif [ "$pct" -le 59 ]; then
    echo '01;36'
  elif [ "$pct" -le 84 ]; then
    echo '38;5;208'
  else
    echo '01;31'
  fi
}

rate_str=""
if [ -n "$five_h" ]; then
  five_h_pct=$(printf '%.0f' "$five_h")
  five_h_color=$(usage_color "$five_h_pct")
  rate_str="\033[${five_h_color}m5h: ${five_h_pct}%${five_h_reset_fmt:+ (\xe2\x86\xbb $five_h_reset_fmt)}\033[00m"
fi
if [ -n "$week" ]; then
  week_pct=$(printf '%.0f' "$week")
  week_color=$(usage_color "$week_pct")
  rate_str="${rate_str:+$rate_str | }\033[${week_color}mwk: ${week_pct}%${week_reset_fmt:+ (\xe2\x86\xbb $week_reset_fmt)}\033[00m"
fi

# Context window usage (ctx tokens + %), colored by usage severity:
# <=14% ochre yellow, 15-40% yellow, 40-59% orange, 60-84% red (dim), 85%+ red (bright)
ctx_color() {
  local pct=${1%.*}
  if [ "$pct" -le 14 ]; then
    echo '38;5;136'
  elif [ "$pct" -le 40 ]; then
    echo '01;33'
  elif [ "$pct" -le 59 ]; then
    echo '38;5;208'
  elif [ "$pct" -le 84 ]; then
    echo '31'
  else
    echo '01;31'
  fi
}

format_tokens() {
  local n=$1
  if [ "$n" -ge 1000000 ]; then
    awk -v n="$n" 'BEGIN{printf "%.1fM", n/1000000}'
  elif [ "$n" -ge 1000 ]; then
    awk -v n="$n" 'BEGIN{printf "%.1fk", n/1000}'
  else
    echo "$n"
  fi
}

ctx_pct_raw=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')

ctx_str=""
if [ -n "$ctx_pct_raw" ]; then
  ctx_pct=$(printf '%.0f' "$ctx_pct_raw")
  ctx_col=$(ctx_color "$ctx_pct")
  tokens_fmt=""
  [ -n "$ctx_tokens" ] && tokens_fmt="$(format_tokens "$ctx_tokens") | "
  if [ -n "$ctx_col" ]; then
    ctx_str="\033[${ctx_col}m${tokens_fmt}${ctx_pct}%\033[00m"
  else
    ctx_str="${tokens_fmt}${ctx_pct}%"
  fi
fi

parts=("$account_label")
[ -n "$model_str" ] && parts+=("$model_str")
[ -n "$rate_str" ] && parts+=("$rate_str")
[ -n "$ctx_str" ] && parts+=("$ctx_str")
parts+=("$git_info")

out="${parts[0]}"
for p in "${parts[@]:1}"; do
  out="${out} | ${p}"
done
printf "%b" "$out"
