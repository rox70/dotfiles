# Orchestrator template

Every project starts from a **local orchestrator**: a git repo, local by default (a remote is
added only on explicit request), that holds the devcontainer, the AI harness (CLAUDE.md,
commands, agents, OpenSpec rules), cross-repo docs and contracts. The real project repos —
one or many (frontend, backend, …) — are cloned **inside** it and never receive any AI file.

```
~/source/repos/<project>/          orchestrator (local git, whitelist .gitignore)
├─ .devcontainer/                  generic image + post-create (clones repos, links overlay)
├─ CLAUDE.md                       orchestrator rules (English, overlay, spec drift, DDI)
├─ .claude/                        command /spec-drift, agents, deny list
├─ repos.conf                      <alias> <folder> <remote-url> [branch]   (1..N repos)
├─ overlay/manifest + <alias>/     AI files symlinked into each child repo and worktree
├─ docs/ contracts/ harness/
├─ scripts/ + Makefile             managed plumbing (refreshed by orch-update)
├─ <project>.code-workspace        generated from repos.conf
├─ <repo-a>/  <repo-b>/            child repos (git-ignored by the orchestrator)
└─ feature-*/ bugfix-*/ …          DDI worktrees (git-ignored)
```

## Create a project

Prerequisite: the machine is set up once (`orch-new` is on the `PATH`); otherwise follow
[`../new-machine/README.md`](../new-machine/README.md) first. Then, for every new project:

1. **Scaffold it** on the host (WSL, or any shell where `install.sh` has run):
   ```bash
   cd ~/source/repos
   orch-new <project> <alias>=git@bitbucket.org:<workspace>/<repo>.git#<branch> \
                      <alias>=git@bitbucket.org:<workspace>/<repo>.git#<branch> ...
   ```
   - `<project>`: the orchestrator folder to create;
   - one `<alias>=<git-url>` per child repo: `<alias>` is a short name used by the `make`
     commands (e.g. `fe`, `be`), `<workspace>/<repo>` the repo's path on the git host;
   - `#<branch>`: the branch each repo is cloned on (e.g. `develop`, `main`); omit it to
     clone the remote's default branch.
2. **Open it in the container**:
   - VS Code: `code <project>` → *Reopen in Container*;
   - from a terminal (plain SSH, no VS Code): `orch-up <project>` then `orch-shell <project>`, see
     [Without VS Code](#without-vs-code-orch-up--orch-shell);
   - no Docker: `cd <project> && make bootstrap` works directly on the host.

   If the build fails while installing a Feature (`failed to solve: process
   "/bin/sh -c cp -ar /tmp/build-features-src/<feature>_N ..." ... exit code: N`), rebuild
   first: Features download packages from nodejs.org, GitHub and packages.microsoft.com, and
   a failed download is the usual cause. If it fails again at the same Feature, the reason is
   in the lines just before `ERROR: failed to build` in the build log; `orch-up <project>` prints
   the whole log in the terminal.
3. **Let the post-create run**: it clones the child repos (`make bootstrap`), generates the
   workspace file, links the overlay and reinstalls the add-ons in `addons.conf`
   (`make addons-sync`; empty in a new project).
4. **First devcontainer on this machine only**: log in to Claude Code (`claude`) and GitHub
   (`gh auth login`), see
   [`../new-machine/README.md`](../new-machine/README.md#5-claude-code-login-and-personal-settings).
   Every later project and rebuild reuses those logins.
5. **Pick the AI tooling** (nothing is preinstalled), see
   [Optional AI tooling](#optional-ai-tooling-add-ons): e.g. `make addon-openspec`,
   `make marketplace NAME=... URL=...`, `make plugin P="..."`.
6. **Describe the project**: each repo's role in `CLAUDE.md`; the toolchains in
   `.devcontainer/devcontainer.json` (Features, or switch `image` to a `build` block reusing
   a child repo's Dockerfile, then rebuild); `docs/`, `contracts/`, `harness/` as needed.

   Claude can do most of it: start `claude` in the orchestrator root (inside the container)
   and give it a prompt like this one. Replace the `<...>` placeholder with what the code
   cannot tell (any language is fine); if you leave it as is or only partly filled in, Claude
   asks you for the missing information instead of guessing it:
   ```text
   Read the child repo(s) listed in repos.conf (README, build files, Dockerfile, .devcontainer/,
   CI config, structure). Do not modify anything inside the child repos.
   Propose, and write only after I approve:
   - the orchestrator's CLAUDE.md: the role of each repo in the table and, only if there is
     more than one, how they communicate and the cross-repo rules; plus this context, which
     is not in the code: <project description, who uses it, constraints,
     environments/installations, external systems it talks to>;
   - the toolchains for .devcontainer/devcontainer.json (Features, or a build block reusing a
     repo's Dockerfile);
   - the content of docs/architecture.md, and of docs/integration.md only if the repos talk
     to each other or to external systems.
   If that project context is still the <...> placeholder, or misses any of the points it
   lists, ask me for the missing information. Ask me about anything else you cannot infer
   from the code instead of guessing.
   ```
7. **Check and save**: `make status` must show no AI files in the child repos; commit the
   orchestrator's own changes (`CLAUDE.md`, `addons.conf`, `devcontainer.json`, …) in its
   local git, including `.devcontainer/devcontainer-lock.json`: the first container build
   writes it to pin the Features' versions, so it shows up untracked; keep it versioned.

`orch-new` copies `template/`, fills `{{PROJECT}}` and the repo table in `CLAUDE.md`, writes
`repos.conf`, generates the workspace file and makes the first local commit. The devcontainer's
post-create then clones the repos (`make bootstrap`) and links the overlay.
Before scaffolding, `orch-new` removes devcontainers still labelled for that path (left by a folder that was
renamed, moved or deleted): VS Code would reuse them instead of building the new config and
fail to attach with exit code 137.

The Claude Code and gh logins are not configured per project: they come from the user-level
`dev.containers.defaultFeatures` (`shared-logins`) plus this repo's `install.sh`.

## Day to day (inside the orchestrator)

| Command | Does |
|---|---|
| `make bootstrap` | clone missing repos, regenerate the workspace, link the overlay |
| `make add-repo ALIAS=api URL=git@… [BRANCH=<branch>]` | register + clone one more repo |
| `make workspace` | regenerate `<project>.code-workspace` from `repos.conf` |
| `make overlay` | adopt new AI files created in a child repo and relink everywhere |
| `make status` | git status of every repo and worktree (must show no AI files) |
| `make pull` | `git pull --ff-only` in every repo |
| `make update` / `orch-update [-n]` | refresh the managed scripts from this template |
| `make addons` / `make addon-<name>` / `make plugin` / `make addons-sync` | list / select + install / reinstall optional AI tooling (see below) |
| `orch-up [--rebuild]` / `orch-shell [cmd]` | start / enter the devcontainer from a terminal, without VS Code (see [below](#without-vs-code-orch-up--orch-shell)) |

## Without VS Code: `orch-up` / `orch-shell`

VS Code is the normal way to open an orchestrator. `orch-up` and `orch-shell` (installed in
`~/.local/bin` by `install.sh`, like `orch-new`) start and enter the same devcontainer from a
plain terminal. Use them:
- on a Linux server reached with plain SSH, where there is no VS Code;
- to build the devcontainer from a terminal and read the **full build log** (e.g. a Feature
  that fails to install: VS Code only shows the last lines);
- to run one-off commands in the container from a script or another shell.

```bash
orch-up [--rebuild] [<orchestrator-dir>]     # build if needed, start, run the post-create
orch-shell [<orchestrator-dir>] [cmd ...]    # login shell in the container, or run cmd
orch-shell ~/source/repos/<project> make status   # example: one command, then exit
```

The directory defaults to the git toplevel of the current directory. `--rebuild` removes the
existing container first, like *Rebuild Container*.

What `orch-up` does: runs `devcontainer up` (the devcontainer CLI; `npx @devcontainers/cli`
when it is not installed) on the orchestrator's `.devcontainer/devcontainer.json`, and adds
what VS Code would take from the user settings:
- the dotfiles repo, cloned into the container and installed with `install.sh` (default: the
  `origin` of this checkout; override with `ORCH_DOTFILES_REPO`);
- the `shared-logins` Feature, so the container shares the Claude and gh logins (override
  with `ORCH_LOGIN_FEATURE`, empty = do not add it).

It warns when the Docker engine is not rootless and several users can log in to the host: the
login volumes would be readable by all of them.

Requirements: Docker and Node.js on the host (for the devcontainer CLI; install it once with
`npm i -g @devcontainers/cli` to avoid the `npx` download).

Containers are identified by the folder path. On WSL, VS Code labels the folder with its
Windows path (`\\wsl.localhost\...`), so a container started by `orch-up` is a **separate**
container from the one VS Code opens: stop it when done
(`docker rm -f $(docker ps -aq --filter label=devcontainer.local_folder=$PWD)` from the
orchestrator folder). Both share the same login volumes.

## Optional AI tooling (add-ons)

Nothing is preinstalled: a new orchestrator has no OpenSpec, no Spec Kit and no plugins.
Inside the container, install only what the project needs, one command each
(`make addon-all` = openspec, speckit, mattpocock and superpowers in one go):

| Command | Installs |
|---|---|
| `make addon-openspec-cli` | OpenSpec CLI (`npm i -g @fission-ai/openspec`), container-wide |
| `make addon-openspec` | OpenSpec CLI + `openspec init --tools claude` in each child repo (`openspec update` when already initialised) |
| `make addon-speckit` | GitHub Spec Kit: `specify init --here --ai claude` in each child repo (installs `uv` if missing) |
| `make addon-mattpocock` | plugin `mattpocock-skills@claude-plugins-official` |
| `make addon-superpowers` | plugin `superpowers@claude-plugins-official` |
| `make plugin P="<name>@<marketplace> ..."` | any Claude Code plugin, one or more |
| `make marketplace NAME=<name> URL=<source>` | register a marketplace other than `claude-plugins-official` (git URL, `owner/repo` or path) |

`REPOS="<alias> ..."` limits an add-on to some child repos (default: all). Plugins are
installed with **project scope** in the orchestrator root and in each child repo, so they
are enabled only for this project; a child repo's `.claude/settings.json` lives in
`overlay/<alias>/` like every other AI file (never pushed). Files created by the `init`
commands are adopted by the overlay automatically. `make addons` shows what is selected
and installed where.

Once adopted, a child repo's `.claude/` and `openspec/` are symlinks to `overlay/<alias>/`.
Claude Code and OpenSpec refuse to write through them ("Path is outside the allowed
directory"), so `addon.sh` runs `claude plugin` and `openspec init`/`update` from
`overlay/<alias>/` itself; the repo and its worktrees see the result through the symlinks.
Run these tools the same way if you call them by hand.

Each command also records the choice in `addons.conf` (`<add-on> [<alias> ...]`,
`plugin <name>@<marketplace> [<alias> ...]`, `marketplace <name> <source>`; versioned in the
orchestrator), so private marketplaces and plugin picks stay in the project, not here.
For example, a project using an internal marketplace:

```bash
make marketplace NAME=<marketplace> URL=git@bitbucket.org:<workspace>/<marketplace-repo>.git
make plugin P="<plugin>@<marketplace> <plugin>@<marketplace>" REPOS="<alias> <alias>"
```

The devcontainer `post-create.sh` runs `make addons-sync`
on every (re)build, which reinstalls each selected add-on at its latest version, so a rebuild
keeps the same tooling and picks up new releases. Delete a line to stop syncing an add-on
(files already installed stay). `post-create.sh` is project-owned: for orchestrators created
before this, `orch-update` prints a hint when it does not run `scripts/addon.sh sync`.

## Guardrails in the template

Claude can read every file of the orchestrated repos, `.env*`, keys and certificates included:
it needs the full picture of their configuration. `.claude/settings.json` only denies running
`git add -f` / `git add --force` (which could push an overlay AI file into a child repo). `CLAUDE.md` adds the rules the deny list cannot
express: English only, overlay files never committed, spec drift checks before OpenSpec work.

## What `orch-update` touches

Only the generic plumbing: `Makefile` and `scripts/*.sh`. Everything else is project-owned
(`CLAUDE.md`, `repos.conf`, `.devcontainer/`, `.claude/`, `docs/`, `overlay/`) and is never
overwritten; template files the project lacks are only listed. Run `orch-update -n` first,
then review `git diff` in the orchestrator and commit.

When changing the template: keep managed files free of project-specific content and of
`{{PLACEHOLDERS}}` (they are copied verbatim by `orch-update`).
