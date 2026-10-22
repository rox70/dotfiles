# ADR 0001 — Local orchestrator
Status: accepted
Decision: {{PROJECT}} is a local orchestrator generated from dotfiles/orchestrator. It holds the
AI scaffold, docs and cross-repo contracts; the child repos are cloned inside it (repos.conf).
The child repos' AI files (CLAUDE.md, DDI docs, openspec/, .claude/) live in overlay/ and are
symlinked into repos and worktrees, ignored via .git/info/exclude: no trace in the child repos.
All artifacts are written in English.
