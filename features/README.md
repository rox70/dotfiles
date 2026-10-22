# Dev Container Features

Features that must act **before** a container exists (mounts), which the dotfiles
`install.sh` cannot do since it runs inside an already created container. They are
published by `.github/workflows/publish-features.yml` as public OCI packages on ghcr.io,
so Dev Containers can pull them without authentication.

## shared-logins

Mounts the Docker **named volumes** holding CLI login state, so one login per tool is
shared by every devcontainer on the same Docker engine and survives rebuilds:

| Volume            | Mounted at              | Holds                                        |
|-------------------|-------------------------|----------------------------------------------|
| `claude-host`     | `/tmp/.claude-host`     | Claude Code default account config/session   |
| `claude-accounts` | `/tmp/.claude-accounts` | one subdirectory per extra Claude account    |
| `shared-logins`   | `/tmp/.shared-logins`   | one subdirectory per other CLI (`gh`, ...)   |

It only declares the mounts: **no credentials**, nothing installed. The dotfiles
`install.sh` links `~/.claude` and `~/.claude.json` to `/tmp/.claude-host`, and
`~/.config/gh` to `/tmp/.shared-logins/gh`. A new tool gets its own subdirectory of
`shared-logins` through `install.sh` alone: no new Feature version.

It replaces `claude-shared-login` (same Claude volumes, plus `shared-logins`). The old
package stays published on ghcr.io, so settings still pointing to it keep working, without
the shared gh login. Never list both: they mount the same targets.

Security note: whatever login the volumes hold is readable by any code that runs in any
devcontainer the Feature is applied to.

### Compose-based devcontainers: a local override is needed

**When:** the project's `devcontainer.json` uses `dockerComposeFile` instead
of `image`/`build`. Single-container projects need nothing: the Feature already mounts the
shared volumes by their exact name.

**Why:** in a compose-based devcontainer the Feature's volumes are declared to compose,
which prefixes them with the project name (`<project>_devcontainer_claude-host`, ...). The
project then gets private, empty copies and every login has to be redone there, separate
from all other devcontainers. Declaring the volumes `external` by their exact name makes
compose use the shared ones.

The setup has two halves: a neutral hook the project commits once, and the volumes, which
only you fill in, locally.

#### 1. Project side: committed once, inert for everyone else

The project loads an optional, gitignored override file and creates it empty when missing.
For example:

```jsonc
// .devcontainer/devcontainer.json
"dockerComposeFile": ["docker-compose.yml", "docker-compose.override.yml"],
"initializeCommand": "test -f .devcontainer/docker-compose.override.yml || printf '# Machine-local, gitignored. Created empty on first start.\\nservices: {}\\n' > .devcontainer/docker-compose.override.yml",
```

```gitignore
# .devcontainer/.gitignore
docker-compose.override.yml
```

`initializeCommand` runs on the host before `docker compose up`, so the second compose file
always exists. A teammate without the `shared-logins` Feature gets the empty stub
(`services: {}`) and nothing changes for them; the volumes never reach the repo.

Listing the override in `dockerComposeFile` is required: compose auto-loads
`docker-compose.override.yml` only when called without `-f`, and Dev Containers passes one
`-f` per listed file. There is no per-user alternative: Dev Containers has no local
`devcontainer.json` override, and it ignores `COMPOSE_FILE` for the same `-f` reason. A
compose project without this hook has to adopt it (one commit) before the shared logins can
work there.

#### 2. Your side: fill the override by hand, once per clone

Replace the stub in `.devcontainer/docker-compose.override.yml` with this, then *Rebuild
Container*:

```yaml
# Machine-local (gitignored). Makes the project use the same login volumes as every
# other devcontainer on this Docker engine (see dotfiles features/README.md).
volumes:
  claude-host:
    name: claude-host
    external: true
  claude-accounts:
    name: claude-accounts
    external: true
  shared-logins:
    name: shared-logins
    external: true
```

Do it once per clone, on every machine: the file is gitignored, so a fresh clone starts
from the empty stub again. Don't delete or `git clean -x` it, or the project falls back to
private, prefixed volumes.

The three volumes must already exist on that Docker engine (`docker volume ls`), otherwise
compose fails on `external`. The host `install.sh` creates them when Docker is running; if
they are still missing (Docker was installed or started after `install.sh`), re-run
`~/dotfiles/install.sh` on the host, or open any single-container devcontainer first, which
makes the Feature create them. Afterwards, `docker volume ls | grep _claude-` should list no
project-prefixed copies.

## Releasing

1. Edit `src/<id>/` and bump `version` in its `devcontainer-feature.json`.
2. Merge to `main`: the workflow publishes `ghcr.io/rox70/dotfiles/<id>:<version>` (and
   the `:<major>` / `:<major>.<minor>` tags). It can also be run by hand (Actions →
   Publish Dev Container Features → Run workflow).
3. First publish of a new Feature only: GitHub → Packages → `dotfiles/<id>` → Package
   settings → Change visibility → **Public**.

Keep volume names and mount targets stable: renaming them loses the shared login.
