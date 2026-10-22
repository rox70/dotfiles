# Set or rename the statusline label of a Claude account

Arguments: $ARGUMENTS (labels use letters, digits, . _ @ -).

- Empty: run `bash -c '. ~/.claude/scripts/claude-accounts.sh && claude_account_list'`, print
  its output, then print exactly `Usage: /account-label <label> | /account-label <existing-label> <new-label>`
  and stop.
- One word, LABEL: label the account currently logged in. Run
  `bash -c '. ~/.claude/scripts/claude-accounts.sh && claude_account_label LABEL'`
  with LABEL replaced by that word.
- Two words, EXISTING then NEW: rename that label (any account, not only the one logged
  in). Run
  `bash -c '. ~/.claude/scripts/claude-accounts.sh && claude_account_rename EXISTING NEW'`
  with EXISTING and NEW replaced by those words.
- More than two words, or a word with any character other than letters, digits, . _ @ -:
  print the usage line above and stop (this check is what makes the words safe to put in
  the commands unquoted).

Print the command output and say the statusline shows the change at its next refresh (for
a rename of an extra profile, new shells use `claude-` followed by the new label).
Do nothing else.
