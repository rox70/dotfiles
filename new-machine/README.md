# Set up a new machine

One procedure for any Linux host: WSL on another PC, another user, or a remote Linux
server. Nothing here depends on a user name or home directory, and no project file needs
editing: every project is an orchestrator created with `orch-new`
(see [`../orchestrator/README.md`](../orchestrator/README.md#create-a-project)).

## In short

Everything below is done **by hand, once per machine and user**; no project command does it
for you (`orch-new` only exists after step 2). From the second project on, none of it is
repeated.

| Step | What you do by hand | What is automatic afterwards |
|---|---|---|
| [1. Prerequisites](#1-prerequisites-on-the-host) | install `git make jq curl` and Docker on the host (`install.sh` adds `jq` and Node.js if missing) | — |
| [2. dotfiles](#2-dotfiles-on-the-host) | `git clone` + `./install.sh` | `orch-*` commands on the `PATH`, Claude Code and `gh` on the host; every devcontainer re-runs `install.sh` by itself (step 3) |
| [3. VS Code settings](#3-vs-code-user-settings-vs-code-hosts-only) | with Docker only: paste two user settings | every devcontainer of every project gets the dotfiles and the `shared-logins` Feature; Settings Sync carries them to your other PCs |
| [5. Claude login](#5-claude-code-login-and-personal-settings) + [6. gh login](#6-github-cli-login) | log in once: in the first devcontainer you open (without Docker: on the host) | with Docker the logins live in shared volumes: every other devcontainer on that engine reuses them, across rebuilds |

Step 4 creates the first project, which is also where the first devcontainer (and so the
logins of steps 5–6) comes from.

The host is WSL or a Linux server, always used through VS Code (a server via Remote-SSH):

| Host | With Docker | Without Docker |
|---|---|---|
| WSL | VS Code Dev Containers, user settings below | the orchestrator runs directly in WSL (`make bootstrap`) |
| Linux server (VS Code Remote-SSH) | VS Code Dev Containers, same user settings; rootless Docker on a shared server | the orchestrator runs directly on the server (`make bootstrap`) |

Without VS Code (plain SSH), `orch-up` / `orch-shell` start the devcontainer through the
devcontainer CLI instead; they also help with VS Code, e.g. to read a full build log (see
[`../orchestrator/README.md`](../orchestrator/README.md#without-vs-code-orch-up--orch-shell)).

Everything is per user: the dotfiles clone, the `orch-*` commands (`~/.local/bin`), the
personal settings and login (`~/.claude*`), the shell rc files and the orchestrators all live
in the user's home. On a host `install.sh` never uses sudo, system-wide packages or `/tmp`
(it installs `jq` and npm packages under `~/.local` when needed); only inside a devcontainer
it uses the container's package manager.

## 1. Prerequisites on the host

Own machine / WSL (you are the only user):

```bash
sudo apt-get update && sudo apt-get install -y git make jq curl ca-certificates
```

plus Docker Engine (or Docker Desktop with WSL integration), with your user in the `docker`
group.

Shared Linux server (several users): keep everything in your profile.
- `git`, `curl`, `make` are normally already there; `jq` is fetched into `~/.local/bin` and
  Node.js (latest LTS, with npm) into `~/.local/node` by `install.sh` if missing.
- Docker must be **rootless** (`dockerd-rootless-setuptool.sh install`, once per user; the
  admin only has to provide the `uidmap` (Debian/Ubuntu; `shadow-utils` on RHEL) and
  `docker-ce-rootless-extras` packages). The orchestrator's `devcontainer.json` needs
  `"remoteUser": "root"` (`orch-new` sets it when it detects rootless Docker): with rootless
  Docker the container's root is your own user on the host, while `vscode` would write files
  owned by an unrelated sub-UID into your repos.
  What the setup tool can still need, with `sudo` or from the admin (seen on RHEL 8 with a
  domain account):
  - a sub-UID/GID range: domain users get none in `/etc/subuid`/`/etc/subgid`. Add one
    keyed by numeric UID (domain names contain `@`), on a range no other line uses:
    `echo "$(id -u):<start>:65536" | sudo tee -a /etc/subuid /etc/subgid`;
  - a user systemd instance: `sudo loginctl enable-linger "$(id -u)"`. If SSH shells still
    have no `XDG_RUNTIME_DIR` (sshd's PAM stack without `pam_systemd`), `install.sh` adds
    the export to your shell rc files: re-run it after enabling linger;
  - the `ip_tables` kernel module, if the tool asks for it (`--skip-iptables` would leave
    containers without outbound network): `sudo modprobe ip_tables` and
    `echo ip_tables | sudo tee /etc/modules-load.d/docker-rootless.conf`;
  - `--force`, when a rootful engine runs on the same host for other users. Then
    `docker context use rootless` makes both the CLI and VS Code use your engine; re-run
    `install.sh` so the shared-login volumes exist in it.
  Coming from a rootful engine, containers that ran as real root may have left root-owned
  files in your home: `~/.claude` is a symlink, so fix its target with
  `sudo chown -R "$(id -u):$(id -g)" ~/.claude-host`. A rootless engine keeps images,
  containers and volumes — including the shared Claude login volumes — under your home;
  with a rootful engine they would be readable by every user of it. Do not ask to be added
  to the `docker` group: it is root-equivalent on the whole server.
- Node.js per user for the devcontainer CLI — the one `install.sh` puts in `~/.local/node`
  when `npm` is missing, or your own (nvm, fnm, a tarball): `npm i -g @devcontainers/cli`
  (with a system Node: `npm config set prefix ~/.local` first).
- No Docker at all: skip the container parts, the orchestrator also runs on the host.

SSH keys for the project remotes go in `~/.ssh` as usual: the devcontainers copy them
read-only.

## 2. dotfiles on the host

```bash
git clone https://github.com/rox70/dotfiles ~/dotfiles     # or your fork
cd ~/dotfiles && ./install.sh && source ~/.bashrc
which orch-new orch-update orch-up orch-shell
```

Clone it exactly once per user and machine (see ["One clone per machine"](../README.md#one-clone-per-machine--never-two)). On the host
`install.sh` also installs Claude Code; warnings about npm/Claude there are harmless if you
only use Claude inside devcontainers.

With Docker installed and running, `install.sh` also creates the `shared-logins` volumes
(`claude-host`, `claude-accounts`, `shared-logins`), so even a compose-based project can be
the first devcontainer you open. Installed Docker afterwards? Re-run `./install.sh`.

## 3. VS Code user settings (VS Code hosts only)

*Preferences: Open User Settings (JSON)* — with Settings Sync on, this follows you to every
PC automatically:

```json
"dotfiles.repository": "rox70/dotfiles",
"dev.containers.defaultFeatures": {
  "ghcr.io/rox70/dotfiles/shared-logins:1": {}
}
```

Coming from the old `claude-shared-login` Feature: **replace** it with `shared-logins`
(never list both: they mount the same targets) and rebuild. The Claude volumes keep their
names, so the existing login is kept.

Use your fork in `dotfiles.repository` if you have one. `orch-up` applies the same two
things without VS Code (override with `ORCH_DOTFILES_REPO`, `ORCH_LOGIN_FEATURE`; see
[`../orchestrator/README.md`](../orchestrator/README.md#without-vs-code-orch-up--orch-shell)).

## 4. Create or move a project

Follow the step-by-step checklist in
[`../orchestrator/README.md` → Create a project](../orchestrator/README.md#create-a-project)
(`orch-new`, open it in the container, logins, AI tooling, `make status`). The first
devcontainer it opens is where steps 5 and 6 below happen.

An orchestrator is local (no remote). To move one to another machine copy the folder
(e.g. `rsync -a` / `tar`), or keep its scaffold in a private remote if you add one; then
`make bootstrap` re-clones any missing child repo.

## 5. Claude Code login and personal settings

The first devcontainer on a Docker engine asks for the login once; it is stored in the
`claude-host` volume and reused by every other devcontainer on that engine, across rebuilds.
Profiles, via `claude-<label> [email]` (bash/zsh; in a plain sh `claude_account_start
<label> [email]`), each creation asking `[Y/n]` first:
- nothing set up yet: `claude-<label>` creates the **default** profile, logs it in and
  registers its email under `<label>`; then `claude` and `claude-<label>` both start it.
  Plain `claude` also creates it, unlabelled.
- default exists, `claude-<label>` unknown: creates an **extra** profile `<label>`, logs
  it in and registers its email under `<label>`.
- an `email` after the label pre-fills the login page (`claude auth login --email`); the
  email actually used is the one registered, with a note when it differs.

Labels live in `~/.claude/account-labels` (one `<email> <label>` line each). The statusline
shows the label of the logged-in email, or the email itself when it has none (an email
never seen before, the first one too, is added unlabelled). `claude-<label>` means the
default profile whenever `<label>` is the label of the default profile's email. Set or
change a label with `/account-label <label>` inside Claude Code (account currently logged
in) or `claude_account_label <label> [email]` in a shell; rename one with
`/account-label <old> <new>` / `claude_account_rename <old> <new>` (an extra profile's
directory, hence its `claude-<old>` alias, is renamed too); `claude_account_list` shows all.

Personal settings are in `~/.claude/dotfiles.conf` (inside containers: in the shared
volume), created by `install.sh`:

```bash
STATUSLINE_TZ="Europe/London"     # time zone of the usage reset times (empty = local)
```

Edit it once from any container; every other container sees the change.

## 6. GitHub CLI login

`install.sh` installs `gh` and, in a container, links `~/.config/gh` to the `gh`
subdirectory of the `shared-logins` volume. Run `gh auth login` once in any devcontainer:
every other devcontainer on that Docker engine (and every rebuild) uses the same login.
Containers have no keyring, so the token is stored in `hosts.yml` inside the volume, as
readable as the Claude login next to it.

The login uses the device flow: `gh` prints a one-time code and
`https://github.com/login/device`. Containers have no clipboard tool, so the
"Failed to copy one-time code to clipboard" warning is harmless: copy the code by hand.
Run from Claude Code as `! gh auth login`, the command moves to the background after two
minutes but keeps waiting; it completes as soon as the code is authorised in the browser.

Moving the login to another machine (optional — logging in again is usually simpler):
`~/dotfiles/scripts/login-volumes.sh backup` on the old host, copy
`~/.claude-login-backup/` securely (it holds live credentials), then `restore` on the new
host.
