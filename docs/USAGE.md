# Usage guide

How to work in AstroAI sessions on the [CANFAR Science Platform](https://www.canfar.net/science-portal). Platform docs are built from [opencadc/canfar](https://github.com/opencadc/canfar) at [opencadc.github.io/canfar](https://opencadc.github.io/canfar/).

| Doc | Audience |
|-----|----------|
| **USAGE.md** (this file) | Session users — quickstart, storage, GPU, tools |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Developers changing this repo |
| [OPERATORS.md](OPERATORS.md) | Platform admins — Harbor push, portal registration |
| [README.md](../README.md) | Repo overview and build commands |

## First five minutes (quick feedback loop)

```bash
astroai-status                    # gpu, disk, project, git — sanity check
gh auth login                     # one-time GitHub setup (token or browser)
astroai-new mylab                 # pixi project on /scratch (or: gh repo clone …)
cd /scratch/mylab
pixi add numpy astropy
pixi run python -c "import astropy; print(astropy.__version__)"
git init && git add -A && git commit -m "start"
gh repo create mylab --private --source=. --push   # or push to an existing remote
astroai-env-save mylab            # lockfile manifest on /arc (~KB)
```

Next session:

```bash
astroai-env-resume mylab
cd /scratch/mylab
pixi run python analysis.py
git push                          # before closing — /scratch is wiped
```

**Commands on every session:** `astroai-help` · `astroai-status` · `less /opt/astroai/USAGE.md`

## Session types

| Image | Best for | CANFAR session type |
|-------|----------|---------------------|
| `webterm` | Shell-first work, tmux, quick scripts | **Contributed** |
| `vscode` | Multi-file projects, extensions, integrated terminal | **Contributed** |
| `notebook` | JupyterLab exploration and teaching notebooks | **Notebook** |
| `marimo` | Reactive notebooks and small dashboards | **Contributed** |

`base` is a headless parent image — not launched directly from the portal.

Launch the image you need from the Science Portal. **CPU and GPU use the same image** — when you need a GPU, select a **GPU node** at launch. The platform attaches the driver; your project supplies CUDA libraries via pixi or uv.

## Storage

| Path | Purpose | Lifetime |
|------|---------|----------|
| `/scratch` | Active repos, pixi projects, checkpoints | **Ephemeral** SSD (~4 days after session ends) |
| `/arc/home/$USER` | Dotfiles, caches, AI tools in `~/.local` | Persistent |
| `/arc/projects/<group>/` | Shared group data (ACL-controlled) | Persistent |
| `/cvmfs/` | DRAC / Alliance software (read-only) | Persistent on nodes; lazy-mounted |

On startup you land in **`/scratch`** (flat mount, not `/scratch/$USER`). Create a project folder there:

```bash
mkdir -p myproject && cd myproject
```

**Back up work with git.** `/scratch` is wiped when the session ends.

## Team workspaces

`/arc/projects/<group>/` is CANFAR's persistent, ACL-controlled shared storage. Use it for team datasets, shared environment manifests, and collaborative results.

### Create a workspace

```bash
astroai-project-init mygroup --members alice,bob
```

Creates `/arc/projects/mygroup/` with `data/`, `results/`, and `env-saves/` subdirectories. The `--members` flag sets POSIX ACLs (`setfacl -R -m u:user:rwx`) so teammates can read and write. Re-run without `--members` to add members later.

```bash
astroai-project-init mygroup --members carol   # add another member
```

### Move data between tiers

**Stage data from persistent storage to `/scratch` for fast I/O:**

```bash
astroai-data-stage /arc/projects/mygroup/data/catalog.fits
# copies catalog.fits → /scratch/catalog.fits

astroai-data-stage /arc/projects/mygroup/survey/  /scratch/survey/
# copies survey/ contents → /scratch/survey/
```

**Sync results from `/scratch` back to persistent storage:**

```bash
astroai-data-sync /scratch/results/  /arc/projects/mygroup/results/
```

Both use `rsync -avh --progress` with source size display. `astroai-data-stage` asks before overwriting an existing target. `astroai-data-sync` warns if the source is not on `/scratch`.

### Team environment saves

Share environment manifests so the whole team can reproduce the same stack:

```bash
cd /scratch/myproject
astroai-env-save myproject --to /arc/projects/mygroup/env-saves/myproject
```

Discover team saves:

```bash
astroai-env-list --team          # team saves only
astroai-env-list --all           # personal + team
```

Resume a team save:

```bash
astroai-env-resume myproject --from /arc/projects/mygroup/env-saves/myproject
```

### Typical team workflow

```bash
# Session start
astroai-env-resume myproject --from /arc/projects/mygroup/env-saves/myproject
astroai-data-stage /arc/projects/mygroup/data/catalog.fits

# Work on /scratch
cd /scratch/myproject
pixi run python analysis.py

# Share results
astroai-data-sync /scratch/results/  /arc/projects/mygroup/results/

# Close
astroai-session-archive
```

## Alliance software (CVMFS)

CANFAR worker nodes mount **CVMFS** — a read-only software tree maintained by the [Digital Research Alliance of Canada](https://docs.alliancecan.ca/) (DRAC / Alliance; same stacks as Fir, Nibi, and other national clusters). It is available in **all** AstroAI sessions and complements the lean image: the container brings `uv`, `pixi`, and basics; CVMFS brings thousands of pre-built packages without bloating the image.

**CANFAR guide** (from [opencadc/canfar](https://github.com/opencadc/canfar/blob/main/docs/platform/cvmfs.md)): [Software Repositories (CVMFS)](https://opencadc.github.io/canfar/platform/cvmfs/)

```bash
# 1. Enable the environment-module system
source /cvmfs/soft.computecanada.ca/config/profile/bash.sh

# 2. Search and load (examples)
module avail python
module load python/3.11
module avail cfitsio
module load cfitsio
```

`ls /cvmfs` alone may look empty — repositories mount **lazily** when you access a known path. Always start from `/cvmfs/soft.computecanada.ca/`.

| Approach | Good for |
|----------|----------|
| **pixi / uv** on `/scratch` | Project-pinned Python stacks, GPU PyTorch, fast iteration, git-tracked deps |
| **CVMFS `module load`** | Alliance-built compilers, libraries, and apps already in the national stack |
| **Image (`apt` / system `uv`)** | Session baseline only — JupyterLab, marimo, shell tooling |

You cannot `pip install` or write into `/cvmfs`. Module changes last for the current shell unless you add the `source` and `module load` lines to `~/.bashrc` on `/arc`.

**More from Alliance docs:** [Using modules](https://docs.alliancecan.ca/wiki/Using_modules) · [Available software](https://docs.alliancecan.ca/wiki/Available_software)

## Typical workflow

**GitHub CLI (`gh`) is pre-installed** — prefer it over raw `git clone` URLs for GitHub repos. SSH keys still live in `~/.ssh` on `/arc`; `gh auth login` handles HTTPS tokens.

### Quick start with `astroai-clone`

Clones and installs deps in one step — detects pixi or uv automatically:

```bash
gh auth login
astroai-clone you/project
cd /scratch/project
pixi run python analysis.py
```

### Manual clone and setup

```bash
# 0. One-time GitHub auth (persisted on /arc)
gh auth login

# 1. Clone or fork
gh repo clone you/project
cd project
# or fork first: gh repo fork owner/upstream --clone

# 2. Install dependencies (into the project — not the system image)
pixi install
# or: uv sync

# 3. Develop and run
pixi run python analysis.py

# 4. Review and share (before closing — /scratch is wiped)
git add -A && git commit -m "session work"
git push                          # existing branch
# or open a PR in one step:
gh pr create --fill
```

### Closing a session

Run `astroai-session-archive` to push code and save your environment in one command:

```bash
astroai-session-archive           # auto-detect project, git push + env save
astroai-session-archive --name my-experiment  # custom save name
```

It prints a summary of what was archived and a contextual `/scratch` wipe reminder.

**Common `gh` commands** (after `gh auth login`):

```bash
gh repo list                      # your repos
gh repo view                      # README + metadata for cwd repo
gh issue list
gh issue view 42
gh pr list
gh pr checkout 17                 # check out a PR branch locally
gh pr diff 17
gh pr view 17 --web               # open in browser (if portal allows)
gh release list                   # tags/releases for cwd repo
gh workflow list                  # GitHub Actions in cwd repo
gh run list --limit 5             # recent CI runs
```

### GPU workflow

1. Launch any AstroAI session on a **GPU node** in the portal.
2. Confirm the device: `nvidia-smi` or `nvtop`.
3. Add GPU deps in your project — the image does **not** ship CUDA libraries:

```bash
cd /scratch/myproject
pixi add torch cuda-version=12
pixi run python train.py
```

Pixi (or uv/pip) downloads CUDA user libraries into the project environment. No separate GPU image is required.

## Command reference

| Command | Purpose |
|---------|---------|
| `astroai-help` | Full command list |
| `astroai-status` | Session snapshot: user, gpu, git, disk |
| `astroai-new [name]` | `pixi init` new project in `/scratch` |
| `astroai-env-save [name]` | Save lockfiles + manifest (~KB) |
| `astroai-env-save name --full` | Also pack `.pixi` or `.venv` with zstd (large) |
| `astroai-env-save name --to /arc/projects/group/env-saves/name` | Team-shared save |
| `astroai-env-resume <name>` | Restore to `/scratch/<name>` and rebuild env |
| `astroai-env-resume <name> --from <path>` | Restore from custom path |
| `astroai-env-list` | List saves under `~/.astroai/saves` |
| `astroai-home-usage` | Disk breakdown under `$HOME` on `/arc` |
| `astroai-cache-prune --all-safe` | Clear pip/uv/npm/pixi package caches |
| `astroai-clone <owner/repo>` | Clone repo to `/scratch` and install deps |
| `astroai-install <tool>` | Install AI coding tools to `~/.local/bin` |
| `astroai-data-stage <src> [dst]` | Copy data from persistent storage to `/scratch` |
| `astroai-data-sync <src> <dst>` | Copy `/scratch` results back to persistent storage |
| `astroai-project-init <name>` | Create team workspace under `/arc/projects` |
| `astroai-session-archive [--name <name>]` | Git push + env save + summary before closing |
| `astroai-debug` | Full diagnostic report (GPU, disk, tools, network) |

## What is pre-installed (needs root)

The image keeps a small **apt** layer: platform essentials and monitoring tools that are not worth pulling in via pixi for every session. **Compilers, dev headers, and science packages go in your pixi project.**

| Tool | Why in the image |
|------|------------------|
| `git`, `git-lfs`, `openssh-client`, `gh`, `delta` | Clone, push, PRs/issues, readable diffs |
| `rg`, `fd`, `bat`, `tree`, `fzf` | Fast search, find, and browse code |
| `tldr` | Quick command examples (`tldr git`) |
| `uv`, `pixi` | Per-project Python environments |
| `htop`, `nvtop`, `procps` | CPU/GPU monitoring |
| `zstd`, `xz-utils`, `bzip2`, `pigz`, `zip`, `unzip` | Archives |
| `curl`, `wget`, `jq`, `rsync` | Fetch data, inspect JSON, sync files |
| `less`, `file`, `vim-tiny` | Logs and quick edits |
| `acl` | CANFAR `/arc` file permissions |

**Not in the image:** `node`/`npm`, AI agent CLIs (`agent`, `claude`, `agy`, `codex`, `freebuff`, `opencode`), `build-essential`, `cmake`, Fortran, CUDA libs, Astropy, PyTorch, etc. Install agents per [AI coding tools](#ai-coding-tools); install Node via [Node.js and npm](#nodejs-and-npm). Many system packages are available via **CVMFS** (`module load`) — see [Alliance software (CVMFS)](#alliance-software-cvmfs).

```bash
pixi add nodejs                                # npm-based CLIs and Lab source extensions
pixi add cmake cxx-compiler fortran-compiler   # only if you compile extensions
pixi add cfitsio                               # instead of libcfitsio-dev
# or: source /cvmfs/.../bash.sh && module load cfitsio
```

## Caches and temp files

Sessions set cache locations in `/etc/profile.d/astroai.sh`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `XDG_CACHE_HOME` | `~/.cache` | Umbrella for tool caches on `/arc` |
| `UV_CACHE_DIR` | `~/.cache/uv` | uv package cache |
| `UV_PYTHON_INSTALL_DIR` | `~/.local/share/uv/python` | uv-managed Python installs (overrides image `/usr/local`) |
| `UV_TOOL_DIR` | `~/.local/share/uv/tools` | uv tool environments |
| `PIP_CACHE_DIR` | `~/.cache/pip` | pip wheel cache |
| `PIXI_HOME` / `PIXI_CACHE_DIR` | `~/.pixi` | pixi environments and package cache |
| `HF_HOME` | `~/.cache/huggingface` | Hugging Face models |
| `TORCH_HOME` | `~/.cache/torch` | PyTorch hub checkpoints |
| `TMPDIR` | `/scratch/.tmp-$USER` | Compile/temp files on SSD |

**Prune stale caches** when `/arc` quota is tight:

```bash
astroai-home-usage
astroai-cache-prune --all-safe
```

Keep **code and git repos on `/scratch`**; keep **caches under `~/.cache` and `~/.pixi`** on `/arc`.

## Save and resume environments

`/arc/home` is **shared CephFS** — keep it small. Active work belongs on `/scratch`; home should hold SSH keys, config, small save **manifests**, and prunable caches.

### Lightweight save (recommended)

```bash
cd /scratch/myproject
pixi add numpy torch cuda-version=12
astroai-env-save myproject
# -> ~/.astroai/saves/myproject/  (pixi.toml, pixi.lock, manifest.json)
```

Next session:

```bash
astroai-env-resume myproject
cd /scratch/myproject
pixi run python train.py
```

Pixi reuses `~/.pixi` package cache on `/arc` when resolving the lockfile — fast without storing another full env in home.

### Full pack (offline / air-gap)

```bash
astroai-env-save myproject --full
astroai-env-save myproject --full --to /arc/projects/mygroup/env-saves/myproject
```

### What belongs where

| Location | Keep | Avoid |
|----------|------|-------|
| `/scratch` | Repos, active `.pixi` env, training outputs | Assuming it persists — `git push` |
| `~/.astroai/saves/` | Lockfile manifests (small) | `--full` packs unless necessary |
| `~/.cache/`, `~/.pixi/cache` | OK — prune with `astroai-cache-prune` | Unbounded HF/torch caches |
| `~/.local/bin` | AI tools, small user binaries | Large vendored SDKs |
| `/arc/projects/<group>/` | Shared datasets, team env-saves | Personal scratch copies |

**Git remains the primary backup** for code. `astroai-env-save` is for environment reproducibility.

## AI coding tools

The image ships **dev CLIs** that pair well with AI assistants (`gh`, `rg`, `fd`, `bat`, `fzf`, `delta`, `tldr`) but does **not** ship AI agent binaries or Node.js — those change too fast to pin.

**One-command install** (recommended):

```bash
astroai-install claude            # or: agent, agy, opencode, codex, freebuff, aider
astroai-install --list            # see all available tools
```

`astroai-install` handles the right installer per tool (curl, gh release download, npm, or uv) and verifies each install. All tools land in `~/.local/bin` on `/arc` (persistent).

**Where to install:** curl/bash installers drop binaries into **`~/.local/bin` on `/arc`** (persistent; already on `PATH`). npm-based tools need [Node.js](#nodejs-and-npm) first — use a pixi project on `/scratch`. Each CLI needs its own API key or account.

### Quick reference

| Tool | Command | Install | Node? |
|------|---------|---------|-------|
| [Cursor Agent](https://cursor.com/docs/cli/overview) | `agent` | curl script | No |
| [Claude Code](https://code.claude.com/docs/en/overview) | `claude` | curl script | No |
| [Antigravity CLI](https://antigravity.google/docs/cli-install) | `agy` | curl script | No |
| [OpenCode](https://dev.opencode.ai/docs/) | `opencode` | curl script (or npm) | Optional |
| [Codex CLI](https://openai-codex.mintlify.app/installation) | `codex` | npm or `gh release download` | npm path only |
| [Freebuff](https://freebuff.com/) | `freebuff` | npm | Yes |

### One-time setup (all curl-installed agents)

```bash
mkdir -p ~/.local/bin
# PATH already includes ~/.local/bin in AstroAI sessions; open a new shell if needed
hash -r
```

### Cursor Agent

```bash
curl -fsS https://cursor.com/install | bash
agent --version
agent auth                       # or set CURSOR_API_KEY
agent                            # interactive session
agent update                     # manual upgrade
```

### Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
claude --version
claude                           # sign in on first run
```

Native install auto-updates in the background. Prefer this over the deprecated npm package `@anthropic-ai/claude-code`.

### Antigravity CLI (Google)

Replacement for Gemini CLI (deprecated June 2026). Free tier via Google account.

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash
agy --version
agy                              # sign in on first run
agy update                       # manual upgrade
```

### OpenCode

Prefer the curl installer (no Node). npm package name is `opencode-ai`, not `opencode`.

```bash
# Recommended — native binary
curl -fsSL https://opencode.ai/install | bash
opencode --version

# Alternative — needs Node (see below)
npm install -g opencode-ai@latest
```

Force install dir to `~/.local/bin` if the script picks another path:

```bash
XDG_BIN_DIR="$HOME/.local/bin" curl -fsSL https://opencode.ai/install | bash
```

### Codex CLI (OpenAI)

**Option A — npm** (needs Node 16+; package is `@openai/codex`, not `codex`):

```bash
# after pixi nodejs setup (see Node.js section)
pixi run npm install -g @openai/codex
codex --version
codex login
```

**Option B — prebuilt binary via `gh`** (no Node; good default on AstroAI):

```bash
# pick the musl tarball matching your arch (x86_64 shown; arm64: codex-aarch64-unknown-linux-musl.tar.gz)
gh release download -R openai/codex -p 'codex-x86_64-unknown-linux-musl.tar.gz' -D /tmp
tar -xzf /tmp/codex-x86_64-unknown-linux-musl.tar.gz -C ~/.local/bin
mv ~/.local/bin/codex-x86_64-unknown-linux-musl ~/.local/bin/codex
codex --version
codex login
```

List available assets: `gh release view -R openai/codex --json assets`.

### Freebuff

npm-only. Requires Node — see [Node.js and npm](#nodejs-and-npm).

```bash
npm install -g freebuff
freebuff --version
cd /scratch/myproject && freebuff
```

If a published npm version fails at runtime, check [CodebuffAI/codebuff issues](https://github.com/CodebuffAI/codebuff/issues) or install from source with `gh repo clone CodebuffAI/codebuff`.

### Pair agents with `gh` and search tools

Agents work best when the repo is already on GitHub and searchable:

```bash
gh auth login
gh repo clone you/project && cd project
rg "def train" --type py          # code search
fd Dockerfile
bat README.md
gh pr list                        # context for the agent
gh issue list
```

**Aider** (Python agent via uv — no Node):

```bash
uv tool install aider-chat
aider --help
```

(`UV_TOOL_DIR` / `UV_TOOL_BIN_DIR` are set in `/etc/profile.d/astroai.sh`.)

Re-run installers when a tool publishes an update, or use each tool's built-in update command (`agent update`, `agy update`, etc.).

## Package managers

### pixi (recommended for conda-style stacks)

```bash
pixi init
pixi add numpy astropy pytorch cuda-version=12
pixi run python script.py
```

### Node.js and npm

The image has **no system `node` or `npm`**. JupyterLab runs without Node (prebuilt pip wheel). You need Node for:

- **npm-based AI agents** — Codex (`@openai/codex`), Freebuff, OpenCode (optional)
- **JupyterLab source extensions** from npm (rare — prefer prebuilt `pip` extensions)

**Prefer curl installers** for Cursor Agent, Claude Code, Antigravity, and OpenCode — they land in `~/.local/bin` on `/arc` and survive `/scratch` expiry. Use Node when npm is the only install path.

#### Recommended: pixi project on `/scratch`

Same pattern as Python stacks. Package cache lands under `~/.pixi` on `/arc`:

```bash
cd /scratch
pixi init node-tools
cd node-tools
pixi add nodejs=22            # or: pixi add nodejs (latest); Codex needs Node 16+

pixi run node --version
pixi run npm --version
```

Install npm CLIs **into the pixi env** (not system-wide):

```bash
# OpenAI Codex
pixi run npm install -g @openai/codex
pixi run codex --version

# Freebuff
pixi run npm install -g freebuff
pixi run freebuff --version

# OpenCode (alternative to curl install)
pixi run npm install -g opencode-ai@latest
pixi run opencode --version
```

Run npm globals through pixi each session:

```bash
cd /scratch/node-tools
pixi run codex
pixi run freebuff
```

Or add shell aliases in `~/.bashrc` on `/arc`:

```bash
alias codex='cd /scratch/node-tools && pixi run codex'
```

#### Persist Node across sessions

```bash
cd /scratch/node-tools
astroai-env-save node-tools     # saves pixi.toml + lockfile to /arc
# next session:
astroai-env-resume node-tools
cd /scratch/node-tools && pixi install
```

Binaries from `npm install -g` inside the pixi env live under `.pixi/` on `/scratch` — they are rebuilt by `pixi install` after resume. For long-lived personal CLIs, prefer curl → `~/.local/bin` or commit the pixi project to git.

#### npm cache and `/arc` quota

`npm` cache defaults to `~/.cache/npm` on `/arc` (`NPM_CONFIG_CACHE`). Prune with `astroai-cache-prune --all-safe` if it grows.

#### Alliance CVMFS (optional)

If you already use modules for other tools, you can load Alliance Node instead of pixi — but **pixi is simpler** for pinning npm CLIs alongside Python deps:

```bash
source /cvmfs/soft.computecanada.ca/config/profile/bash.sh
module avail nodejs
module load nodejs/22          # version varies; check module avail
node --version && npm --version
npm install -g @openai/codex   # installs to your user prefix; ensure ~/.local/bin is on PATH
```

### uv (recommended for pip/venv workflows)

```bash
uv init
uv add numpy torch
uv run python script.py
```

## Session-specific notes

### webterm

Browser terminal on port **5000**. Persistent `tmux` session named `astroai` (reattach after refresh). Login shell (`bash -l`). Starship prompt.

```bash
# inside tmux after reconnect:
tmux attach -t astroai
```

### vscode

OpenVSCode Server on port **5000**. Integrated terminal uses bash. Extensions persist under `/arc`.

### notebook

JupyterLab on port **8888** (Notebook session type). Starts in `/scratch` via `common-init.sh`. Proxy base URL: `session/notebook/<session-id>`.

The image ships `jupyter lab` via pip — **no Node required** to run Lab. Add extensions with `pip` when possible:

```bash
pixi add jupyterlab-git    # prebuilt extension, no Node
```

Source extensions from npm need Node — add `nodejs` to a pixi project on `/scratch` (see [Node.js and npm](#nodejs-and-npm)).

### marimo

Reactive notebooks on port **5000**. Create `.py` notebooks in `/scratch` from the marimo UI. Uses `--base-url` when `skaha_sessionid` is set.

## Environment variables (platform)

Skaha typically sets:

- `HOME` → `/arc/home/$USER`
- `USER`, UID/GID — injected non-root identity
- `skaha_sessionid` — reverse-proxy paths (**Contributed** sessions: webterm, vscode, marimo)
- `JUPYTER_TOKEN` — session ID on **Notebook** sessions (same value as Skaha session ID)
- GPU devices — on GPU nodes, via the container runtime

## Diagnostics

`astroai-debug` produces a comprehensive snapshot of your session — useful for troubleshooting, sharing with collaborators, or attaching to support requests.

```bash
astroai-debug                     # save to ~/.astroai/debug-<timestamp>.log + print
astroai-debug --stdout            # print only
astroai-debug --file /path/out    # save to custom path
```

The report covers:

| Section | What it shows |
|---------|---------------|
| Session | Home, PWD, scratch mount, tmp, shell, uptime |
| Profile | ASTROAI_PROFILE_LOADED, PATH, uv/pixi/cache dirs |
| GPU | nvidia-smi summary and processes (or CPU node notice) |
| Disk | /scratch and HOME `df`, top directories by size |
| Tools | Version check for git, gh, uv, pixi, jq, rg, fd, bat, and more |
| Project | Pixi/uv detection, lockfile size, env size |
| Network | Reachability check for pypi.org, github.com, conda |
| Environment | Key env vars (sanitized — tokens and keys hidden) |
| Processes | Top 10 by CPU |
| CVMFS | `/cvmfs/soft.computecanada.ca` status |

Share the log file: `cat ~/.astroai/debug-<timestamp>.log`

## Troubleshooting

| Problem | Things to try |
|---------|----------------|
| Lost work after session | Was it only on `/scratch`? Use `git push` before closing. |
| `git clone` SSH fails | Add your key to `~/.ssh` on `/arc`. |
| GPU not visible | Did you pick a GPU node? Run `nvidia-smi`. |
| `import torch` no CUDA | GPU node + `cuda-version` / GPU torch via pixi. |
| AI CLI not found | Curl installers → `~/.local/bin`; npm tools → pixi `nodejs` project (see [AI coding tools](#ai-coding-tools)). |
| `node` / `npm` not found | Not in the image — `pixi add nodejs` in a project on `/scratch` (see [Node.js and npm](#nodejs-and-npm)). |
| `gh: not authenticated` | Run `gh auth login` once; token persists on `/arc`. |
| Wrong npm package | Codex: `@openai/codex` · OpenCode: `opencode-ai` · Claude Code: use curl install, not npm. |
| pip build fails | Add compilers/libs with pixi, not system apt. |
| `uv`: Permission denied on `/usr/local/share/uv` | Image `ENV` is root-only; `source /etc/profile.d/astroai.sh` (or `bash -l`) **must** run — it force-sets `UV_PYTHON_INSTALL_DIR` to `~/.local/share/uv/python`. Check with `astroai-status`. |
| `/arc` quota pressure | `astroai-home-usage`; `astroai-cache-prune --all-safe`. |
| `ls /cvmfs` looks empty | Normal — CVMFS mounts lazily; `source /cvmfs/soft.computecanada.ca/config/profile/bash.sh` then `module avail`. |
| Jupyter 404 behind proxy | Notebook session must use port **8888** and `/skaha/startup.sh` — see [OPERATORS.md](OPERATORS.md). |
| tmux shell is nologin | Image sets `default-shell /bin/bash`; use `bash -l` in webterm. |
