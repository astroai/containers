# Runtime usage

How to work in AstroAI sessions on the [CANFAR Science Platform](https://www.canfar.net/science-portal). For building and publishing images, see [README.md](../README.md). Operators: [OPERATORS.md](OPERATORS.md).

## First five minutes (quick feedback loop)

```bash
astroai-status                    # gpu, disk, project, git — sanity check
astroai-new mylab                 # pixi project on /scratch (or: git clone …)
cd /scratch/mylab
pixi add numpy astropy
pixi run python -c "import astropy; print(astropy.__version__)"
git init && git add -A && git commit -m "start"
astroai-env-save mylab            # lockfile manifest on /arc (~KB)
```

Next session:

```bash
astroai-env-resume mylab
cd /scratch/mylab
pixi run python analysis.py
git push                          # before closing — /scratch is wiped
```

**Commands on every session:** `astroai-help` · `astroai-status` · `less /opt/astroai/RUNTIME.md`

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

On startup you land in **`/scratch`** (flat mount, not `/scratch/$USER`). Create a project folder there:

```bash
mkdir -p myproject && cd myproject
```

**Back up work with git.** `/scratch` is wiped when the session ends.

## Typical workflow

```bash
# 1. Clone (SSH keys in ~/.ssh on /arc)
git clone git@github.com:you/project.git
cd project

# 2. Install dependencies (into the project — not the system image)
pixi install
# or: uv sync

# 3. Develop and run
pixi run python analysis.py

# 4. Before closing the session
git add -A && git commit -m "session work" && git push
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
| `astroai-cache-prune --all-safe` | Clear pip/uv/pixi package caches |
| `astroai-install-ai` | Seed Cursor `agent` (auto on webterm/vscode start) |
| `astroai-update-ai` | Refresh Cursor `agent` in `~/.local` |

Legacy aliases: `install-ai-tools` → `astroai-install-ai`, `update-ai-tools` → `astroai-update-ai`.

## What is pre-installed (needs root)

The image keeps a small **apt** layer: platform essentials and monitoring tools that are not worth pulling in via pixi for every session. **Compilers, dev headers, and science packages go in your pixi project.**

| Tool | Why in the image |
|------|------------------|
| `git`, `git-lfs`, `openssh-client` | Clone and push over SSH |
| `uv`, `pixi` | Per-project Python environments |
| `htop`, `nvtop`, `procps` | CPU/GPU monitoring |
| `zstd`, `xz-utils`, `bzip2`, `pigz`, `zip`, `unzip` | Archives |
| `curl`, `wget`, `jq`, `rsync` | Fetch data, inspect JSON, sync files |
| `less`, `file`, `vim-tiny` | Logs and quick edits |
| `acl` | CANFAR `/arc` file permissions |

**Not in the image:** `build-essential`, `cmake`, Fortran, CUDA libs, Astropy, PyTorch, etc.

```bash
pixi add cmake cxx-compiler fortran-compiler   # only if you compile extensions
pixi add cfitsio                               # instead of libcfitsio-dev
```

## Caches and temp files

Sessions set cache locations in `/etc/profile.d/astroai.sh`:

| Variable | Default | Purpose |
|----------|---------|---------|
| `XDG_CACHE_HOME` | `~/.cache` | Umbrella for tool caches on `/arc` |
| `UV_CACHE_DIR` | `~/.cache/uv` | uv package cache |
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

**Default CLI: Cursor `agent`.** We do not bake in every AI CLI — they change often, bloat the image, and install cleanly into `~/.local`.

`webterm` and `vscode` seed `agent` on first start (only if missing). Installs land in **`~/.local/bin` on `/arc`**.

```bash
agent --help
astroai-update-ai
```

Optional CLIs (user-installed):

```bash
curl -fsSL https://opencode.ai/install | bash
```

`notebook` and `marimo` do not auto-install AI tools. Use `webterm` or `vscode` for agent-assisted coding.

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

Add Lab extensions in the project if needed: `pixi add jupyterlab-git`

### marimo

Reactive notebooks on port **5000**. Create `.py` notebooks in `/scratch` from the marimo UI. Uses `--base-url` when `skaha_sessionid` is set.

## Environment variables (platform)

Skaha typically sets:

- `HOME` → `/arc/home/$USER`
- `USER`, UID/GID — injected non-root identity
- `skaha_sessionid` — reverse-proxy paths (**Contributed** sessions: webterm, vscode, marimo)
- `JUPYTER_TOKEN` — session ID on **Notebook** sessions (same value as Skaha session ID)
- GPU devices — on GPU nodes, via the container runtime

## Troubleshooting

| Problem | Things to try |
|---------|----------------|
| Lost work after session | Was it only on `/scratch`? Use `git push` before closing. |
| `git clone` SSH fails | Add your key to `~/.ssh` on `/arc`. |
| GPU not visible | Did you pick a GPU node? Run `nvidia-smi`. |
| `import torch` no CUDA | GPU node + `cuda-version` / GPU torch via pixi. |
| `agent` not found | Open `webterm` or `vscode` once, or `astroai-update-ai`. |
| pip build fails | Add compilers/libs with pixi, not system apt. |
| `/arc` quota pressure | `astroai-home-usage`; `astroai-cache-prune --all-safe`. |
| Jupyter 404 behind proxy | Notebook session must use port **8888** and `/skaha/startup.sh` — see [OPERATORS.md](OPERATORS.md). |
| tmux shell is nologin | Image sets `default-shell /bin/bash`; use `bash -l` in webterm. |
