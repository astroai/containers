# Getting started with AstroAI sessions

Welcome! AstroAI sessions give you a ready-to-go development environment on the
[CANFAR Science Platform](https://www.canfar.net/science-portal) — a browser
terminal, VS Code, JupyterLab, or Marimo notebook with Python, git, compilers,
and astronomy tools already set up. You pick a session type, the platform
launches a container, and you're coding in seconds.

This guide walks you through your first session and then covers everything else.
Platform docs live at
[opencadc.github.io/canfar](https://opencadc.github.io/canfar/)
(source: [opencadc/canfar](https://github.com/opencadc/canfar)).

| Doc | Audience |
|-----|----------|
| **USAGE.md** (this file) | Session users — getting started, storage, GPU, tools |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Developers changing this repo |
| [OPERATORS.md](OPERATORS.md) | AstroAI maintainers — build, push, register images on CANFAR |
| [README.md](../README.md) | Repo overview and build commands |

---

## Your first session

### 1. Pick a session type

Go to the [Science Portal](https://www.canfar.net/science-portal) and launch one
of these images:

| Image | What you get | Portal session type |
|-------|-------------|---------------------|
| `webterm` | Browser terminal with tmux — fast, lightweight | **Contributed** |
| `vscode` | Full VS Code in the browser — extensions, integrated terminal | **Contributed** |
| `notebook` | JupyterLab — great for exploration and teaching | **Notebook** |
| `marimo` | Reactive Python notebooks | **Contributed** |

All four images share the same tools and storage model. **CPU and GPU use the
same image** — if you need a GPU, pick a **GPU node** when you launch. The
platform attaches the driver; your project supplies CUDA libraries via pixi or uv.

> `base` is the headless parent image used for CI jobs and local Docker runs —
> you don't launch it from the portal.

### 2. Set up GitHub (once)

GitHub CLI (`gh`) is pre-installed. Authenticate once and the token persists
across sessions:

```bash
gh auth login
```

Follow the prompts — browser auth or paste a token. Done.

### 3. Start a project

```bash
canfar-lab status                    # quotas, home/project space, processes
canfar-lab init mylab                 # creates a pixi project in the work directory
cd mylab
pixi add numpy astropy
pixi run python -c "import astropy; print(astropy.__version__)"
```

Or clone an existing repo:

```bash
canfar-lab clone you/project         # clones + installs deps automatically
cd project
pixi run python analysis.py

# reuse your saved ML stack (AstroAI-only bootstrap — see below)
canfar-lab clone --from-env ml-base you/other-project
```

### 4. Save your work before closing

**This is important.** Your work directory (`TMP_SRC_DIR`, default `/srcdir`)
and scratch (`TMP_SCRATCH_DIR`, default `/scratch`) are both ephemeral — they
get wiped when the session ends. Think of them as fast desks you work on, not
filing cabinets.

```bash
git add -A && git commit -m "session work"
git push                          # code → GitHub
canfar-lab save mylab            # lockfile manifest → /arc (tiny, ~KB)
```

Or do both at once:

```bash
canfar-lab push           # git push + env save in one command
```

### 5. Resume next time

```bash
canfar-lab resume mylab          # restores lockfiles, rebuilds env
cd mylab
pixi run python analysis.py
```

That's it — you're up and running. The rest of this guide covers storage details,
GPU workflows, team workspaces, and everything else.

**Handy commands:** `canfar-lab guide` · `canfar-lab status` · `canfar-lab status` · `less /opt/astroai/USAGE.md`

---

**On this page:** [Storage](#how-storage-works) · [Team workspaces](#team-workspaces) · [CADC clients](#cadc--canfar-clients) · [CVMFS](#alliance-software-cvmfs) · [Workflows](#workflows) · [Commands](#command-reference) · [Caches](#caches-and-temp-files) · [AI agents](#ai-coding-tools) · [Session notes](#session-specific-notes) · [Troubleshooting](#troubleshooting)

---

## How storage works

CANFAR sessions mount **two ephemeral directories** (Kubernetes `emptyDir`,
wiped when the session ends). AstroAI keeps code and data separate:

| Variable / path | What it's for | How long it lasts |
|-----------------|--------------|-------------------|
| **`TMP_SRC_DIR`** (default **`/srcdir`**) | Git repos, pixi/uv projects, workspace bundles | **Ephemeral** |
| **`TMP_SCRATCH_DIR`** (default **`/scratch`**) | Staged datasets, training outputs, download caches, `TMPDIR` | **Ephemeral** |
| `/arc/home/$USER` | SSH keys, dotfiles, env save manifests, AI tools, ML caches | **Persistent** |
| `/arc/projects/<group>/` | Shared team data (ACL-controlled) | **Persistent** |
| `/cvmfs/` | DRAC / Alliance software (read-only) | Persistent on nodes; lazy-mounted |

On Contributed session startup, `common-init` **`cd`s to `TMP_SRC_DIR`**.
Run `canfar-lab doctor` to see resolved paths (`TMP_SRC_DIR`, `TMP_SCRATCH_DIR`, caches).

### The golden rule

**Code goes in `TMP_SRC_DIR`, gets backed up with `git push`.** Both ephemeral
directories are fast but temporary. Your home on `/arc` is persistent but smaller
and slower — use it for config, caches, and small manifests.

### Overriding the defaults

You can set custom paths at launch (Skaha `extraEnv`, headless `canfar create --env`, or `docker run -e`):

```bash
TMP_SRC_DIR=/custom/code
TMP_SCRATCH_DIR=/custom/scratch
```

Legacy alias: `ASTROAI_WORK_ROOT` still works when `TMP_SRC_DIR` is unset.

### What goes where

| Location | Keep here | Avoid |
|----------|----------|-------|
| **`TMP_SRC_DIR`** (`/srcdir`) | Repos, active `.pixi`/`.venv` envs | Assuming it persists — always `git push` |
| **`TMP_SCRATCH_DIR`** (`/scratch`) | Staged datasets, training outputs, download caches | Assuming it persists — `canfar-lab data sync` |
| `~/.astroai/saves/` | Lockfile manifests (small) | `--full` packs unless necessary |
| `~/.cache/huggingface` | OK — `canfar-lab clean home --hf` | Large model re-downloads |
| `~/.cache/torch`, matplotlib, other ML | `canfar-lab clean home --ml` | Unbounded caches |
| `~/.local/bin` | AI tools, small user binaries | Large vendored SDKs |
| `/arc/projects/<group>/` | Shared datasets, team env-saves | Personal scratch copies |

### Periodic reminders

Interactive sessions nudge you about ephemeral storage every ~2 hours with a
yellow banner showing how long you've been working and how many commits you've
made. There's also a quota reminder if your `/arc` home gets above 80%.

When you close a login shell inside a git repo, AstroAI tries a quiet
`git push` and env save in the background (once per session). It won't commit
for you — commit first for a clean history.

---

## Save and resume environments

### Lightweight save (recommended)

Saves lockfiles and a small manifest (~KB) to `/arc`:

```bash
cd "${TMP_SRC_DIR}/myproject"
pixi add numpy torch cuda-version=12
canfar-lab save myproject
# → ~/.astroai/saves/myproject/  (pixi.toml, pixi.lock, manifest.json)
```

Next session, pixi rebuilds from the lockfile using cached packages:

```bash
canfar-lab resume myproject
cd "${TMP_SRC_DIR}/myproject"
pixi run python train.py
```

### Full pack (for offline or air-gapped use)

Packs the entire `.pixi` or `.venv` directory with zstd compression:

```bash
canfar-lab save myproject --full
canfar-lab save myproject --full --to /arc/projects/mygroup/env-saves/myproject
```

### Offline batch (workspace freeze)

For headless jobs with no network, freeze a full project tree:

```bash
cd "${TMP_SRC_DIR}/mylab"
canfar-lab workspace save mylab --with-cache
# next session or batch job:
canfar-lab workspace restore mylab
cd "${TMP_SRC_DIR}/mylab" && pixi run python job.py
```

Bundles live under `TMP_SRC_DIR/.astroai/workspaces/` (ephemeral unless you
copy them to `/arc` first).

**Git remains the primary backup** for code. `canfar-lab save` is for
environment reproducibility.

### Shared dependency stacks (AstroAI bootstrap)

When several projects use the same heavy stack (torch, CUDA, etc.), save a
template once and reuse it when cloning:

```bash
# one-time: create and save your standard stack
canfar-lab init ml-base
cd "${TMP_SRC_DIR}/ml-base"
pixi add python=3.12 numpy torch cuda-version=12
canfar-lab save ml-base
# optional team copy:
canfar-lab save ml-base --to /arc/projects/mygroup/env-saves/ml-base

# later: clone with warm caches (+ lock bootstrap if repo has no lockfile)
canfar-lab clone --from-env ml-base you/project-a
canfar-lab clone --from-env ml-base --from /arc/projects/mygroup/env-saves/ml-base you/project-b
```

What `--from-env` does (session-local only):

1. Installs the saved env in a temp dir to warm `PIXI_CACHE_DIR` / `UV_CACHE_DIR`
2. If the cloned repo has **no** `pixi.lock` / `uv.lock`, copies one from the save
   as a bootstrap (never overwrites lockfiles already in git)
3. If the copied lock doesn't match the repo's manifest, falls back to `pixi lock` /
   `uv lock` automatically

**Portable / OSS projects:** the cloned repo is never modified with AstroAI-specific
files. Outside AstroAI, users only need standard project files in git:

```bash
git clone https://github.com/you/project.git
cd project
pixi install    # or: uv sync
pixi run python analysis.py
```

Before publishing, commit lockfiles generated from **that** repo's manifest so
non-AstroAI users get reproducible installs:

```bash
pixi lock && git add pixi.lock && git commit -m "Add lockfile"
```

---

## Team workspaces

`/arc/projects/<group>/` is CANFAR's persistent shared storage with POSIX ACLs.
Great for team datasets, shared environment manifests, and collaborative results.

### Create one

```bash
canfar-lab project init mygroup --members alice,bob
```

Creates `/arc/projects/mygroup/` with `data/`, `results/`, and `env-saves/`
subdirectories, and sets read/write ACLs. Add more members later:

```bash
canfar-lab project init mygroup --members carol
```

### Moving data around

**Stage data from persistent storage to scratch for fast I/O:**

```bash
canfar-lab data stage /arc/projects/mygroup/data/catalog.fits
# → ${TMP_SCRATCH_DIR}/catalog.fits

canfar-lab data stage /arc/projects/mygroup/survey/  "${TMP_SCRATCH_DIR}/survey/"
```

**Sync results back to persistent storage:**

```bash
canfar-lab data sync "${TMP_SCRATCH_DIR}/results/"  /arc/projects/mygroup/results/
```

Both use `rsync -avh --progress`. `canfar-lab data stage` asks before overwriting;
`canfar-lab data sync` warns if the source isn't under `TMP_SCRATCH_DIR`.

### Share environment saves with your team

```bash
cd "${TMP_SRC_DIR}/myproject"
canfar-lab save myproject --to /arc/projects/mygroup/env-saves/myproject
```

Teammates can discover and use them:

```bash
canfar-lab saves --team
canfar-lab resume myproject --from /arc/projects/mygroup/env-saves/myproject
```

### A typical team session

```bash
# Start
canfar-lab resume myproject --from /arc/projects/mygroup/env-saves/myproject
canfar-lab data stage /arc/projects/mygroup/data/catalog.fits

# Work
cd "${TMP_SRC_DIR}/myproject"
pixi run python analysis.py

# Share and close
canfar-lab data sync "${TMP_SCRATCH_DIR}/results/"  /arc/projects/mygroup/results/
canfar-lab push
```

---

## CADC / CANFAR clients

The OpenCADC Python clients are **pre-installed** in every session (venv at
`/opt/astroai/venv/cadc`, already on your PATH):

| Package | CLI examples | What it does |
|---------|--------------|---------|
| `cadcdata` | `cadcget`, `cadcput`, `cadcinfo` | CADC archive data access |
| `cadctap` | `cadc-tap` | TAP catalog queries |
| `vos` | `vcp`, `vls` | VOSpace storage |
| `canfar` | `canfar auth login`, `canfar sessions …` | Science Platform API/CLI |

### Authentication

```bash
canfar auth login              # Science Platform (recommended)
cadc-get-cert -u $USER         # X509 cert for vos / cadcdata (netrc also works)
```

### Examples

```bash
cadcget cadc:CFHT/806045o.fits
cadc-tap "SELECT * FROM caom2.Observation WHERE collection='CFHT' LIMIT 5"
vls vos:/
canfar sessions list
```

### Using CADC packages in your own code

For `import cadcdata` in project Python code, add packages to your pixi/uv
project so versions stay consistent:

```bash
pixi add cadcdata cadctap vos canfar
# or: uv add cadcdata cadctap vos canfar
```

---

## Alliance software (CVMFS)

CANFAR worker nodes mount **CVMFS** — a read-only software tree maintained by
the [Digital Research Alliance of Canada](https://docs.alliancecan.ca/) (the
same stacks you'd find on Fir, Nibi, and other national clusters). Available
in all AstroAI sessions.

**CANFAR guide:** [Software Repositories (CVMFS)](https://opencadc.github.io/canfar/platform/cvmfs/) ([source](https://github.com/opencadc/canfar/blob/main/docs/platform/cvmfs.md))

```bash
# Enable the module system
source /cvmfs/soft.computecanada.ca/config/profile/bash.sh

# Search and load
module avail python
module load python/3.11
module avail cfitsio
module load cfitsio
```

> **Tip:** `ls /cvmfs` may look empty — repositories mount **lazily**. Always
> start from `/cvmfs/soft.computecanada.ca/`.

### When to use what

| Approach | Best for |
|----------|----------|
| **pixi / uv** under `TMP_SRC_DIR` | Project-pinned Python stacks, GPU PyTorch, fast iteration, git-tracked deps |
| **CVMFS `module load`** | Alliance-built compilers, libraries, and apps already in the national stack |
| **Image tools (system)** | Session baseline — JupyterLab, marimo, CADC clients, shell tooling |

You can't `pip install` or write into `/cvmfs`. Module changes last for the
current shell unless you add them to `~/.bashrc` on `/arc`.

**More from Alliance docs:** [Using modules](https://docs.alliancecan.ca/wiki/Using_modules) · [Available software](https://docs.alliancecan.ca/wiki/Available_software)

---

## Workflows

### Clone and go

```bash
gh auth login                     # once
canfar-lab clone you/project         # clones + installs deps
cd project
pixi run python analysis.py
```

Or manually:

```bash
gh repo clone you/project
cd project
pixi install                      # or: uv sync
```

### Creating a new project

```bash
canfar-lab init mylab                 # pixi project in TMP_SRC_DIR
cd mylab
pixi add numpy astropy matplotlib
pixi run python analysis.py

# Put it on GitHub
git init && git add -A && git commit -m "start"
gh repo create mylab --private --source=. --push
```

`canfar-lab init` also supports `--uv`, `--no-git`, `--no-gh`, and `--astro`.

### Closing a session

```bash
canfar-lab push           # git push + env save + summary
canfar-lab push --name my-experiment
canfar-lab --yes push   # non-interactive (used by the exit hook)
```

### GPU workflow

1. Launch any AstroAI session on a **GPU node** in the portal.
2. Confirm the device: `nvidia-smi` or `nvtop`.
3. Add GPU deps in your project:

```bash
cd "${TMP_SRC_DIR}/myproject"
pixi add torch cuda-version=12
pixi run python train.py
```

No separate GPU image needed — pixi downloads CUDA user libraries into the
project environment.

### GitHub tips

```bash
gh repo list                      # your repos
gh repo view                      # README for cwd repo
gh issue list
gh pr list
gh pr create --fill               # open a PR in one step
gh pr checkout 17                 # check out a PR branch
gh release list
gh run list --limit 5             # recent CI runs
```

---

## Command reference

| Command | What it does |
|---------|-------------|
| `canfar-lab guide` | Full command list (this doc is the long form) |
| `canfar-lab status` | Quotas, home/project space, top processes |
| `canfar-lab init [name]` | New project under `TMP_SRC_DIR` (`--uv`, `--no-git`, `--no-gh`, `--astro`) |
| `canfar-lab clone <owner/repo> [dir]` | Clone + install deps (`--from-env`, `--from`) |
| `canfar-lab save [name]` | Save lockfiles + manifest (~KB) (`--full`, `--to`) |
| `canfar-lab resume <name>` | Restore + rebuild env (`--from`, `[path]`) |
| `canfar-lab saves` | List saves (`--team`, `--all`) |
| `canfar-lab workspace save [name]` | Freeze full project tree for offline batch (`--with-cache`, `--to`) |
| `canfar-lab workspace restore <name>` | Restore frozen workspace — no network (`--from`, `--to`) |
| `canfar-lab kernel register` | Register project as Jupyter kernel (`--list`, `--unregister`, `--name`) |
| `canfar-lab push` | Git push + env save before closing (`--name`, `--force`) |
| `canfar-lab project init <name>` | Team workspace on `/arc/projects` (`--members`) |
| `canfar-lab data stage <src> [dst]` | Copy persistent → scratch |
| `canfar-lab data sync <src> <dst>` | Copy scratch → persistent |
| `canfar-lab status` | Disk breakdown under `$HOME` |
| `canfar-lab clean home` | Clear re-downloadable junk on `/arc` (`--all-safe`, `--stale-pkg`, `--ml`, `--hf`, `--dry-run`) |
| `canfar-lab clean cache` | Clear scratch download caches (`--all-safe`, `--pip`, `--uv`, `--npm`, `--pixi`, `--conda`, `--hf`) |
| `canfar-lab agent install <tool>` | Install AI tools to `~/.local/bin` (`--list`) |
| `canfar-lab agent models free` | Apply free-tier model presets (OpenRouter + Kilo) |
| `canfar-lab doctor` | Diagnostic report (`--stdout`, `--file`) |

Most `astroai-*` commands support `-h` (short summary on stderr, exit 1) and
`--help` (detailed help on stdout, exit 0). `canfar-lab guide` prints this index.

```bash
canfar-lab clean cache --help
canfar-lab save -h
```

---

## What's pre-installed

The image ships a curated set of tools so you can be productive immediately.
Heavy ML stacks and project-specific deps belong in **your** pixi/uv project.

| Tool | Why it's included |
|------|-------------------|
| `git`, `git-lfs`, `openssh-client`, `gh`, `delta` | Clone, push, PRs/issues, readable diffs |
| `rg`, `fd`, `bat`, `tree`, `fzf`, `ctags`, `hyperfine` | Fast search, find, browse, benchmark, jump to definitions |
| `sg` (ast-grep) | Syntax-aware search — `canfar-lab agent install ast-grep` if missing |
| `file`, `xxd`, `hexdump` | Inspect file types and binary contents |
| `patch`, `make`, `shellcheck` | Apply diffs, run Makefiles, lint shell scripts |
| `gcc`, `g++`, `gfortran`, `ld`, `ar` | GNU C/C++/Fortran + linkers (default for science builds) |
| `rustc`, `cargo` | Rust builds |
| `cmake`, `ninja`, `pkg-config` | Build systems and library discovery |
| `autoconf`, `automake`, `libtool`, `flex`, `bison` | Legacy `./configure` / autotools tarballs |
| `libcfitsio-dev`, `libfftw3-dev`, `libgsl-dev` | Common astronomy/science headers |
| `lsof`, `ss`, `host` | Debug open files, sockets, DNS |
| `ncdu` | Explore disk usage interactively |
| `tldr` | Quick command examples (`tldr git`) |
| `uv`, `pixi`, `micromamba` (`mamba`) | Per-project Python / conda environments |
| `htop`, `nvtop`, `procps` | CPU/GPU monitoring |
| `zstd`, `xz-utils`, `bzip2`, `pigz`, `zip`, `unzip` | Archives |
| `curl`, `wget`, `jq`, `rsync` | Fetch data, inspect JSON, sync files |
| `less`, `vim-tiny` | Logs and quick edits |
| `acl` | CANFAR `/arc` file permissions |

**Not in the image:** `node`/`npm`, AI agent CLIs, CUDA libs, Astropy, PyTorch,
HDF5/NetCDF/OpenBLAS dev packages. Install agents via
[AI coding tools](#ai-coding-tools); install Node via
[Node.js and npm](#nodejs-and-npm).

```bash
pixi add nodejs                                # npm-based CLIs
pixi add hdf5 netcdf4 openblas                 # heavier science libs
# or: source /cvmfs/.../bash.sh && module load cfitsio hdf5
```

**Compilers:** `gcc`/`g++`/`gfortran` cover C, C++, and Fortran. `cargo build`
for Rust. Need Clang/LLVM? Use CVMFS or `pixi add clangxx`.

---

## Package managers

### pixi (recommended for conda-style stacks)

```bash
pixi init
pixi add numpy astropy pytorch cuda-version=12
pixi run python script.py
```

### uv (recommended for pip/venv workflows)

```bash
uv init
uv add numpy torch
uv run python script.py
```

### micromamba / mamba (standalone conda)

`micromamba` is pre-installed (`mamba` is a symlink). Create envs under
`TMP_SRC_DIR` with a project-local prefix:

```bash
cd "${TMP_SRC_DIR}/myenv"
micromamba create -p ./env -c conda-forge python=3.12 numpy astropy
micromamba activate ./env
python -c "import astropy; print(astropy.__version__)"
```

For pixi projects, conda-channel downloads go through `PIXI_CACHE_DIR` —
you don't need micromamba unless you want a classic conda workflow.

### Node.js and npm

The image has **no system `node` or `npm`** — JupyterLab runs without Node
(prebuilt pip wheel). You need Node for:

- **npm-based AI agents** (Pi, CodeWhale, Freebuff, Codex, OpenCode)
- **JupyterLab source extensions** from npm (rare — prefer pip extensions)

**Recommended: `canfar-lab agent install node`** — installs Node.js persistently to
`~/.local/bin` on `/arc`. Alternatively: pixi project under **`TMP_SRC_DIR`**
or `module load nodejs` from CVMFS.

#### pixi project approach

```bash
cd "${TMP_SRC_DIR}"
pixi init node-tools && cd node-tools
pixi add nodejs=22

pixi run node --version
pixi run npm --version

# Install npm CLIs into the pixi env
pixi run npm install -g @openai/codex
pixi run npm install -g @earendil-works/pi-coding-agent
pixi run npm install -g codewhale
pixi run npm install -g freebuff
```

Run them with `pixi run codex`, `pixi run pi`, etc., or add aliases to
`~/.bashrc` on `/arc`.

#### Persist Node across sessions

```bash
cd "${TMP_SRC_DIR}/node-tools"
canfar-lab save node-tools
# next session:
canfar-lab resume node-tools
cd "${TMP_SRC_DIR}/node-tools" && pixi install
```

npm globals inside the pixi env rebuild with `pixi install`. For long-lived
CLIs, prefer `canfar-lab agent install node`.

#### CVMFS alternative

```bash
source /cvmfs/soft.computecanada.ca/config/profile/bash.sh
module load nodejs/22
node --version && npm --version
npm install -g @openai/codex
```

---

## AI coding tools

The image ships **dev CLIs** that pair well with AI assistants (`gh`, `rg`, `fd`,
`bat`, `fzf`, `delta`, `tldr`) but does **not** ship AI agent binaries or
Node.js — those change too fast to bundle.

### One-command install

```bash
canfar-lab agent install kilo             # Kilo CLI (free tier via kilo-auto/free)
canfar-lab agent install goose            # Goose (OpenRouter / MCP)
canfar-lab agent install cline            # Cline CLI (needs npm)
canfar-lab agent install agent            # Cursor Agent
canfar-lab agent install claude           # Claude Code
canfar-lab agent install node             # Node.js + npm (needed for cline, pi, …)
canfar-lab agent install --list           # see everything available
```

Binaries land in `~/.local/bin` on `/arc` — they persist across sessions.

### AI coding agents (3 commands)

One setup for **all users** — config persists on `/arc` across sessions.

```bash
gh auth login
canfar-lab agent setup              # once: MCP + rules + GitHub skills + free-model presets
canfar-lab agent install kilo       # or goose, cline, opencode, codex, agent, …
canfar-lab agent models free        # OpenRouter :free + Kilo configs (no credit card key)
```

**After an image upgrade** (operators ship new skills/MCP defaults):

```bash
canfar-lab agent update
```

**Inside a git repo** (optional, commit to share with teammates):

```bash
canfar-lab agent project
```

What you get:

| Piece | Purpose |
|-------|---------|
| MCP (Context7, GitHub, memory, fetch) | Docs lookup, GitHub, persistence |
| Cursor/Claude/Goose/OpenCode/Codex configs | Same MCP everywhere you work |
| Rules | AstroAI paths, Python, efficient search |
| GitHub skills | [ast-grep](https://github.com/ast-grep/agent-skill), [skill-forge](https://github.com/pavelzw/skill-forge) (matplotlib, pr-review, …) |
| `canfar-lab-workflow` skill | CANFAR cheat sheet for agents |

Then use **normal commands** — nothing extra to memorize:

```bash
pixi install && pixi run python script.py
uv sync && uv run pytest -q
rg 'pattern' --type py
```

Check install: `cat ~/.canfar/lab/agent-setup-stamp`

Advanced: `canfar-lab agent setup --list` for per-agent bundles; `canfar-lab agent setup --help`

### What's available

| Tool | Command | Install method | Needs Node? |
|------|---------|----------------|-------------|
| [Cursor Agent](https://cursor.com/docs/cli/overview) | `agent` | curl script | No |
| [Claude Code](https://code.claude.com/docs/en/overview) | `claude` | curl script | No |
| [Antigravity CLI](https://antigravity.google/docs/cli-install) | `agy` | curl script | No |
| [OpenCode](https://dev.opencode.ai/docs/) | `opencode` | curl script (or npm) | Optional |
| [Codex CLI](https://openai-codex.mintlify.app/installation) | `codex` | npm or `gh release download` | npm path only |
| [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/set-up/install-copilot-cli) | `copilot` | curl script | No |
| [Goose](https://block.github.io/goose/) | `goose` | curl script | No |
| [Kilo CLI](https://kilo.ai/docs/code-with-ai/agents/cli) | `kilo` | curl script (or npm) | Optional |
| [Cline CLI](https://docs.cline.bot/cline-cli/overview) | `cline` | npm | Yes |
| [Pi Coding Agent](https://pi.dev/) | `pi` | npm | Yes |
| [CodeWhale](https://www.codewhale.ai/) | `codewhale` | npm | Yes |
| [Swival](https://swival.dev/) | `swival` | `uv tool install` | No |
| [Freebuff](https://freebuff.com/) | `freebuff` | npm | Yes |

> Google's Gemini CLI was replaced by **Antigravity CLI** (`agy`).

### Which one should I use?

| You want… | Start with |
|-----------|------------|
| Cursor subscription / IDE workflow | **Cursor Agent** — `canfar-lab agent install agent` |
| Deep reasoning, long refactors | **Claude Code** — `canfar-lab agent install claude` |
| Google account; Gemini successor | **Antigravity CLI** — `canfar-lab agent install agy` |
| GitHub-native, issue → PR | **GitHub Copilot CLI** — `canfar-lab agent install copilot` |
| OpenAI ChatGPT / Codex | **Codex CLI** — `canfar-lab agent install codex` |
| Model-agnostic, 75+ providers | **OpenCode** — `canfar-lab agent install opencode` |
| MCP + recipes, Block/Linux Foundation | **Goose** — `canfar-lab agent install goose` |
| Free tier, no API key to start | **Kilo** — `canfar-lab agent install kilo` then `kilo auth` |
| OpenRouter free models (key, no card) | **Any OpenRouter agent** — `export OPENROUTER_API_KEY=…` then `canfar-lab agent models free` |
| Minimal harness, BYOK | **Pi** — needs Node |
| Open models / DeepSeek-first TUI | **CodeWhale** — needs Node |
| Local models (LM Studio, Ollama) | **Swival** — `canfar-lab agent install swival` |
| Budget npm agent | **Freebuff** — needs Node |

You can install several agents — they share `gh`, `rg`, and repos but use
separate auth. Each CLI needs its own account or API key.

### Swival with local models

```bash
canfar-lab agent install swival

swival "Summarize the README"                    # LM Studio on localhost
swival --provider openrouter --model z-ai/glm-5 "Refactor error handling"
swival --provider generic --base-url http://host:1234/v1 --model my-model "Review this diff"
cd "${TMP_SRC_DIR}/myproject" && swival --repl   # interactive
```

### Pair agents with search tools

```bash
gh auth login
gh repo clone you/project && cd project
rg "def train" --type py          # code search
fd Dockerfile
bat README.md
gh pr list                        # context for the agent
```

Re-run installers to update, or use each tool's built-in update command
(`agent update`, `agy update`, etc.).

---

## Caches and temp files

Sessions configure cache locations in `/etc/profile.d/astroai.sh`. When
`TMP_SCRATCH_DIR` is writable (default `/scratch`), **package download caches**
go there — not under `$HOME`:

| Variable | Default (scratch mounted) | Purpose |
|----------|---------------------------|---------|
| `TMP_SRC_DIR` | `/srcdir` | Code root |
| `TMP_SCRATCH_DIR` | `/scratch` | Data staging + download caches |
| `UV_CACHE_DIR` | `${TMP_SCRATCH_DIR}/.cache-$USER/uv` | uv package cache |
| `PIP_CACHE_DIR` | `${TMP_SCRATCH_DIR}/.cache-$USER/pip` | pip wheel cache |
| `NPM_CONFIG_CACHE` | `${TMP_SCRATCH_DIR}/.cache-$USER/npm` | npm download cache |
| `PIXI_CACHE_DIR` | `${TMP_SCRATCH_DIR}/.cache-$USER/pixi` | pixi package cache |
| `PIXI_HOME` | `~/.pixi` | pixi global config on `/arc` |
| `MAMBA_PKGS_DIRS` | `${TMP_SCRATCH_DIR}/.cache-$USER/conda/pkgs` | micromamba/conda cache |
| `CONDA_PKGS_DIRS` | same as `MAMBA_PKGS_DIRS` | conda-compatible alias |
| `MAMBA_ROOT_PREFIX` | `~/.local/share/micromamba` | micromamba config on `/arc` |
| `TMPDIR` | `${TMP_SCRATCH_DIR}/.tmp-$USER` | Compile/temp files on SSD |
| `UV_PYTHON_INSTALL_DIR` | `~/.local/share/uv/python` | uv-managed Python installs |
| `UV_TOOL_DIR` | `~/.local/share/uv/tools` | uv tool environments |
| `XDG_CACHE_HOME` | `~/.cache` | ML/tool caches on `/arc` |
| `HF_HOME` | `~/.cache/huggingface` | Hugging Face models |
| `TORCH_HOME` | `~/.cache/torch` | PyTorch hub checkpoints |

If scratch isn't mounted, caches fall back under `TMP_SRC_DIR/.cache-$USER/`.

When `/arc` quota feels tight:

```bash
canfar-lab status                  # see what's using space
canfar-lab clean home --dry-run --all-safe   # preview /arc cleanup
canfar-lab clean home --all-safe       # stale pkg caches, ML, logs on /arc
canfar-lab clean home --hf              # also drop Hugging Face models (expensive)
canfar-lab clean cache --all-safe        # scratch: pip/uv/npm/pixi/conda caches
```

---

## Session-specific notes

### webterm

Browser terminal on port **5000**. A persistent `tmux` session named `astroai`
auto-starts — if you refresh the page, your work is still there:

```bash
tmux attach -t astroai            # reattach after reconnect
```

**tmux tabs** (prefix `Ctrl-b`):

| Keys | Action |
|------|--------|
| `Ctrl-b` `c` | New window (tab) |
| `Ctrl-b` `n` / `p` | Next / previous window |
| `Ctrl-b` `0`–`9` | Jump to window number |
| `Ctrl-b` `w` | Interactive window list |
| `Ctrl-b` `%` / `"` | Split pane vertical / horizontal |

For real GUI-style tabs, use the **vscode** session instead.

### vscode

OpenVSCode Server on port **5000**. Integrated terminal uses bash. Extensions
persist under `/arc` across sessions.

### notebook

JupyterLab on port **8888** (select **Notebook** session type in the portal —
not Contributed).

**Stock CANFAR (most deployments today):** Skaha runs the platform script
`/skaha-system/start-jupyterlab.sh`, not AstroAI's `/skaha/startup.sh`. You'll
see the file browser at **`/`** (not `TMP_SRC_DIR`), no AstroAI welcome banner,
and some harmless deprecation warnings in the logs. Everything still works — `cd`
to `TMP_SRC_DIR` and use pixi/uv normally.

**With platform launch override:** When CANFAR ops point notebook jobs at
`/skaha/startup.sh`, you get `common-init`, cwd `TMP_SRC_DIR`, and proper
`base_url`. See [OPERATORS.md](OPERATORS.md) for the helm change request.

**No Node needed** to run JupyterLab. Add extensions with pip when possible:

```bash
pixi add jupyterlab-git    # prebuilt extension, no Node needed
```

#### Project kernels

JupyterLab does **not** auto-detect environments under `TMP_SRC_DIR`. After
creating or resuming a project, register it:

```bash
cd "${TMP_SRC_DIR}/myproject"
canfar-lab kernel register
```

Then pick **Python (myproject · pixi)** in the kernel menu.

| Command | What it does |
|---------|-------------|
| `canfar-lab kernel register` | Register cwd project (adds `ipykernel` if missing) |
| `canfar-lab kernel register "${TMP_SRC_DIR}/other"` | Register a specific path |
| `canfar-lab kernel register --name mylab` | Override kernel display name |
| `canfar-lab kernel register --list` | List registered kernels |
| `canfar-lab kernel register --unregister` | Remove kernel for this project |

Kernelspecs persist on `/arc`. The env binaries live on `TMP_SRC_DIR` —
**re-run `canfar-lab kernel register` after each `canfar-lab resume`**.

### marimo

Reactive notebooks on port **5000**. Create `.py` notebooks under `TMP_SRC_DIR`
from the marimo UI.

---

## Environment variables (platform and AstroAI)

Skaha typically injects:

- `HOME` → `/arc/home/$USER`
- `USER`, UID/GID — your non-root identity
- `skaha_sessionid` — reverse-proxy routing (Contributed sessions)
- `JUPYTER_TOKEN` — session ID (Notebook sessions)
- GPU devices — on GPU nodes, via the container runtime

AstroAI profile (`/etc/profile.d/astroai.sh`) sets unless overridden:

| Variable | Image default | Purpose |
|----------|---------------|---------|
| `ASTROAI_DEFAULT_SRC_DIR` | `/srcdir` | Default code root when `TMP_SRC_DIR` unset |
| `ASTROAI_DEFAULT_SCRATCH_DIR` | `/scratch` | Default scratch when `TMP_SCRATCH_DIR` unset |
| `TMP_SRC_DIR` | resolved at login | Code, git repos, pixi/uv projects |
| `TMP_SCRATCH_DIR` | `/scratch` | Datasets, download caches, `TMPDIR` parent |
| `ASTROAI_WORK_ROOT` | — | Legacy alias for code root (deprecated) |

Run `canfar-lab doctor` to see resolved values.

---

## Diagnostics

When something isn't working, `canfar-lab doctor` produces a comprehensive snapshot:

```bash
canfar-lab doctor                     # save to ~/.astroai/debug-<timestamp>.log + print
canfar-lab doctor --stdout            # print only
canfar-lab doctor --file /path/out    # save to custom path
```

| Section | What it shows |
|---------|---------------|
| Session | Home, `TMP_SRC_DIR`, `TMP_SCRATCH_DIR`, tmp, shell, uptime |
| Profile | ASTROAI_PROFILE_LOADED, PATH, uv/pixi/cache dirs |
| GPU | nvidia-smi summary and processes (or CPU node notice) |
| Disk | `TMP_SRC_DIR`, `TMP_SCRATCH_DIR`, and HOME `df`, top dirs |
| Tools | Version check for git, gh, uv, pixi, jq, rg, fd, bat, and more |
| Project | Pixi/uv detection, lockfile size, env size |
| Network | Reachability check for pypi.org, github.com, conda |
| Environment | Key env vars (sanitized — tokens and keys hidden) |
| Processes | Top 10 by CPU |
| CVMFS | `/cvmfs/soft.computecanada.ca` status |

Share the log: `cat ~/.astroai/debug-<timestamp>.log`

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| Lost work after session | Was code only in `TMP_SRC_DIR` without `git push`? Always push before closing. |
| `git clone` SSH fails | Add your key to `~/.ssh` on `/arc`, or use `gh auth login` for HTTPS. |
| GPU not visible | Did you pick a GPU node at launch? Run `nvidia-smi`. |
| `import torch` — no CUDA | Need GPU node **and** `cuda-version` in your pixi/uv project. |
| AI CLI not found | `canfar-lab agent install <tool>` or `canfar-lab agent install --list`. npm agents need `canfar-lab agent install node` first. |
| `node` / `npm` not found | Not in the image — `canfar-lab agent install node` or `pixi add nodejs`. See [Node.js and npm](#nodejs-and-npm). |
| `gh: not authenticated` | `gh auth login` — token persists on `/arc`. Required for `canfar-lab agent install codex`. |
| Wrong npm package | Codex: `@openai/codex` · OpenCode: `opencode-ai` · Pi: `@earendil-works/pi-coding-agent` · Claude/Cursor: prefer curl via `canfar-lab agent install`. |
| pip build fails | Add compilers/libs with pixi, not system apt. |
| `uv` permission denied on `/usr/local` | `source /etc/profile.d/astroai.sh` (or `bash -l`) must run first — it redirects uv paths to `~/.local`. Check with `canfar-lab doctor`. |
| `canfar` / `cadcget` not found | Open a login shell (`bash -l`) or new tmux window. Run `/opt/astroai/bin/canfar-verify.sh`. |
| `/arc` quota pressure | `canfar-lab status` then `canfar-lab clean home --all-safe`. |
| `ls /cvmfs` looks empty | Normal — CVMFS mounts lazily. `source /cvmfs/soft.computecanada.ca/config/profile/bash.sh` then `module avail`. |
| Jupyter 404 behind proxy | Notebook sessions use port **8888** and path `/session/notebook/<id>/`. See [OPERATORS.md](OPERATORS.md). |
| Jupyter opens at `/` not project dir | Stock platform launcher — `cd "${TMP_SRC_DIR}"` manually or ask ops for the AstroAI startup override. |
| Kernel missing after resume | Re-run `canfar-lab kernel register` in the project dir (`TMP_SRC_DIR` paths change between sessions). |
| Contributed session 404 | Skaha strips `/session/contrib/<id>` before forwarding; webterm must not use `--base-path`. Update to latest image tag. |
| tmux shell is nologin | Image sets `default-shell /bin/bash`; try `bash -l` in webterm. |
