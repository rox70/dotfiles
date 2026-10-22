# {{PROJECT}} — local orchestration workspace

**Local by default.** This orchestrator is a local git repo: add a remote or push it only when
the user explicitly asks. Whatever happens to it, nothing in it (AI harness, overlay, OpenSpec,
docs, contracts, harness/) ever goes into the child repos or their remotes.
It contains these independent git repositories (`repos.conf`):

| Alias | Folder | Role |
|-------|--------|------|
{{REPO_TABLE}}

DDI worktrees are created next to them (`feature-*`, `bugfix-*`, `hotfix-*`, `release-*`).
Check `git rev-parse --show-toplevel` / `git remote -v` to know which repo a worktree belongs to.

## Local-only AI files (critical)
- In the child repos and their worktrees, the paths listed in `overlay/manifest`
  (`CLAUDE.md`, `docs/project-metadata.md`, `docs/commands.md`, `docs/conventions.md`,
  `openspec/`, `.claude/`, `AGENTS.md`, …) are **symlinks to `overlay/<alias>/`** and
  git-ignored via `.git/info/exclude`.
- Never commit, `git add -f`, un-ignore or copy them into the repos. Never edit
  `.gitignore` of a child repo to handle them. OpenSpec artifacts are local.
- Do not modify tracked files (README, `.github/copilot-instructions.md`, …) just for
  AI setup purposes. Only real product changes go into commits and PRs.
- After any tool creates new AI files, run `make overlay`; `make status` must show
  no AI-related untracked files.

## Language
- **Everything written into the repositories and this orchestrator is in English**:
  code, comments, commit messages, branch names, PR titles/descriptions, docs, OpenSpec
  artifacts, CLAUDE.md, skills, commands. This applies even when the conversation is in
  another language.

## Rules
- State the target repo before editing. One branch and one PR per repo.
- Repo-specific rules live in each repo's `CLAUDE.md` (Project Config) and win inside that repo.
- DDI workflow skills run with the working directory **inside** a child repo or its
  worktree, never from this root.
- Large/architectural changes: `ddi-opsx-dev-cycle` (OpenSpec, local `openspec/` per repo).
  A change to a contract between child repos = one change per repo, both linking
  `contracts/` and an ADR. Prefer backward-compatible contract changes.
- Everything runs inside the devcontainer.

## Spec drift
- OpenSpec specs are local and colleagues never update them: they can become stale.
- Before starting any OpenSpec change (or ddi-opsx-dev-cycle) on a capability that already has a
  spec, run `/spec-drift <alias> <capability>` and resolve DRIFT-SPEC items first.
- After a bugfix or manual change that alters specified behaviour, or after pulling colleagues'
  commits touching specified areas, run `/spec-drift` and sync the spec.

## Where things are
- `docs/` architecture, integration between the child repos, `adr/`
- `contracts/` schemas / samples / API specs shared by the child repos
- `harness/` local integration environment
- `overlay/` local AI files of the child repos (`overlay/manifest` lists them)
- `make bootstrap | overlay | status | pull | add-repo | update` (see `Makefile`)
