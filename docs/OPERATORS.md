# Publishing & registration guide

For **AstroAI project maintainers** who build, push, and register `images.canfar.net/astroai/*` session images on the CANFAR Science Platform.

**Not for CANFAR platform admins.** Skaha deployment, Helm charts, and launch scripts live in [opencadc/science-platform](https://github.com/opencadc/science-platform). This repo has **no write access** there — only image build/push and Science Portal registration within the `astroai` Harbor project. Platform changes are **feature requests or bug reports** to the CANFAR/science-platform team.

| Role | Scope | Where |
|------|--------|--------|
| **AstroAI maintainer** (this doc) | Build, push, register images; smoke-test on CANFAR | astroai-containers, Harbor `astroai/`, Science Portal |
| **CANFAR platform admin** | Skaha Helm, launch scripts, ingress, cluster config | opencadc/science-platform |

## Images and session types

| Image | Harbor path | Skaha session type | Port | User-facing |
|-------|-------------|-------------------|------|-------------|
| `base` | `images.canfar.net/astroai/base:<tag>` | *(not launched)* | — | Headless parent only |
| `webterm` | `images.canfar.net/astroai/webterm:<tag>` | **Contributed** | 5000 | Browser terminal |
| `vscode` | `images.canfar.net/astroai/vscode:<tag>` | **Contributed** | 5000 | Browser IDE |
| `notebook` | `images.canfar.net/astroai/notebook:<tag>` | **Notebook** | 8888 | JupyterLab |
| `marimo` | `images.canfar.net/astroai/marimo:<tag>` | **Contributed** | 5000 | Reactive notebooks |
| `full` | `images.canfar.net/astroai/full:<tag>` | *(not launched)* | — | Base + Node.js LTS (`npm` CLIs) |

Each image carries `io.canfar.skaha.session.type` in its OCI labels (`headless`, `contributed`, or `notebook`) for Harbor inventory.

## Harbor registry (public project)

Images live at `images.canfar.net/astroai/<image>:<tag>`. The **`astroai` Harbor project must be public** so CANFAR Skaha and Science Portal users can pull session images without registry credentials.

In Harbor (`https://images.canfar.net`):

1. Open project **astroai** → **Configuration**.
2. Set **Access Level** to **Public**.
3. Confirm anonymous pull works (no `docker login` required):

```bash
docker logout images.canfar.net 2>/dev/null || true
docker pull images.canfar.net/astroai/base:latest
```

Push still requires maintainer credentials (`docker login images.canfar.net`). Only **pull** is anonymous.

**Skaha note:** Harbor public pull works for `docker pull`, but `canfar create` with `astroai/*` images may still require `canfar config set registry.*` (Harbor username + CLI secret) for headless maintainer tests until the platform catalogs the project. Science Portal session launches for registered image types do not require users to configure registry auth.

`test-canfar.sh` tries without registry credentials first, then retries with `docker login` credentials if present.

Build and push:

```bash
make build-all
make push/notebook TAG=26.06
make push/webterm TAG=26.06
```

Do **not** register `base` as a Science Portal session — it is the shared parent layer.

## CANFAR platform boundary ([opencadc/science-platform](https://github.com/opencadc/science-platform))

Skaha session Jobs are rendered from Helm templates under `helm/skaha-config/`. Shared launch scripts live in `helm/launch-scripts/` and are mounted via `helm/templates/launch-scripts-configmap.yaml` at `/skaha-system/`. **AstroAI maintainers cannot change these** — use this section to know what is image-side vs what to request from CANFAR ops.

**What AstroAI controls vs what CANFAR platform controls:**

| Session type | Helm template | Container command | AstroAI `/skaha/startup.sh` runs? | Log/startup notes |
|--------------|---------------|-------------------|-----------------------------------|-------------------|
| **Contributed** (webterm, vscode, marimo) | `launch-contributed.yaml` | Image `CMD` (not overridden) | **Yes** | Image fixes apply (`common-init`, `/scratch`, quiet quota on non-TTY, etc.) |
| **Notebook** | `launch-notebook.yaml` | **`/skaha-system/start-jupyterlab.sh`** (platform ConfigMap) | **No** (unless helm override) | Platform script uses deprecated `--NotebookApp.*` CLI flags; sets `JUPYTER_*` under `/arc/home` |
| **Headless** | `launch-headless.yaml` | User command / image `CMD` | Depends on image | Used for maintainer smoke tests (`test-canfar.sh`) |

Stock platform notebook launcher (`helm/launch-scripts/start-jupyterlab.sh`):

```bash
jupyter lab \
  --NotebookApp.base_url=session/notebook/"$1" \
  --NotebookApp.notebook_dir=/ \
  --NotebookApp.allow_origin="*" \
  --ServerApp.base_url=session/notebook/"$1" \
  ...
```

That script is **not in astroai-containers** — Jupyter `NotebookApp → ServerApp` migration warnings, `root_dir=/`, and missing `common-init` on notebook sessions are **CANFAR platform behaviour** until the science-platform team changes `launch-notebook.yaml` or modernizes `start-jupyterlab.sh`.

**Contributed sessions:** ingress path stripping is platform-defined (`ingress-contributed.yaml`); listen on `/` and set proxy URL flags in our startup scripts — do not fight the platform path model.

**Do not try to paper over platform notebook startup in the image alone** — `launch-notebook.yaml` overrides `command`/`args` and mounts `/skaha-system`. Image-side `startup-notebook.sh` only runs if CANFAR platform ops apply a launch override (see below).

## Contributed sessions (webterm, vscode, marimo)

Register as **Contributed** in the Science Portal.

- `skaha_sessionid` is set in the container environment
- Browser URL: `/session/contrib/<session-id>/` (ingress strips that prefix before forwarding to the container)
- Container listens on port **5000** at `/` (see proxy table below)
- Image entrypoint: `/skaha/startup.sh` → `/cadc/startup-<image>.sh`
- Platform does not override the container command

## Notebook sessions (notebook image only)

Register `images.canfar.net/astroai/notebook:<tag>` as a **Notebook** session type.

**Default (stock science-platform):** Skaha runs `/skaha-system/start-jupyterlab.sh` — not AstroAI `startup-notebook.sh`. Expect:

- `NotebookApp` deprecation warnings in session logs (harmless; from platform CLI flags)
- Jupyter `root_dir` / `notebook_dir` = `/` (platform script), not `/scratch`
- No AstroAI `common-init` (welcome banner, cache dirs, quota check)
- `JUPYTER_CONFIG_DIR`, `JUPYTER_PATH`, etc. pointed at `/arc/home/.../.jupyter/` by `launch-notebook.yaml`

**With helm override (recommended for AstroAI notebook):**

- Session ID passed as the **first argument** to `/skaha/startup.sh`
- `JUPYTER_TOKEN` also set to the session ID (platform default)
- Reverse-proxy path: `/session/notebook/<session-id>/`
- Container listens on port **8888**
- Jupyter `base_url`: `session/notebook/<session-id>` (matches platform convention)
- AstroAI `common-init`, `/scratch` cwd, `/etc/jupyter` config

### Requesting CANFAR platform changes (notebook)

The stock notebook job in `helm/skaha-config/launch-notebook.yaml` runs `/skaha-system/start-jupyterlab.sh` from the launch-scripts ConfigMap. That script skips AstroAI session setup.

**File an issue or feature request** with the CANFAR/science-platform team. Example asks:

1. **Per-image launch override** — run AstroAI notebook images with `/skaha/startup.sh` instead of `/skaha-system/start-jupyterlab.sh`:

```yaml
containers:
- name: "${skaha.jobname}"
  image: ${software.imageid}
  command: ["/skaha/startup.sh"]
  args:
  - ${skaha.sessionid}
  ports:
  - containerPort: 8888
    protocol: TCP
    name: notebook-port
```

(Remove or replace the `start-jupyterlab` ConfigMap volume mount when using this override.)

2. **Upstream launcher fix** (benefits all notebook images) — modernize `helm/launch-scripts/start-jupyterlab.sh` to use `--ServerApp.*` only instead of deprecated `--NotebookApp.*` flags.

## Session log expectations (CANFAR console)

When reviewing `canfar logs`, distinguish platform noise from image issues:

| Source | Examples | Fixable in astroai-containers? |
|--------|----------|--------------------------------|
| **Platform notebook launcher** | `NotebookApp` migration warnings; `root_dir=/` | No — science-platform `start-jupyterlab.sh` |
| **Image (contributed)** | Quota banner, CADC `SyntaxWarning`, verify job-control spam | Yes — shipped in `26.06+` |
| **Upstream apps** | ttyd `__lws_lc_*` INFO; OpenVSCode reconnection grace message | No — harmless INFO |

Contributed session log audits should target **errors/failures** and AstroAI startup lines; notebook log audits on stock CANFAR should expect the three Jupyter migration warnings until the science-platform team updates the launcher.

## Image entrypoints

| Image | `/skaha/startup.sh` | `CMD` |
|-------|---------------------|-------|
| `webterm` | → `startup-webterm.sh` | `/skaha/startup.sh` |
| `vscode` | → `startup-vscode.sh` | `/skaha/startup.sh` |
| `notebook` | → `startup-notebook.sh "$@"` | `/skaha/startup.sh` |
| `marimo` | → `startup-marimo.sh` | `/skaha/startup.sh` |

Contributed images listen on port **5000**. The Skaha ingress **strips** `/session/contrib/<session-id>` before forwarding (Traefik `replacePathRegex` in `ingress-contributed.yaml`), so the container receives requests at `/`.

| Image | In-container listen path | Proxy config flag | Purpose |
|-------|-------------------------|-------------------|---------|
| `webterm` | `/` | *(none — do not use ttyd `--base-path`)* | ttyd matches incoming paths |
| `vscode` | `/` | `--server-base-path /session/contrib/<id>` | OpenVSCode URL generation |
| `marimo` | `/` | `--base-url /session/contrib/<id>` | marimo URL generation |

Notebook sessions are different: ingress does **not** strip the path, so Jupyter `base_url` must be `session/notebook/<session-id>`.

## Science Portal checklist (AstroAI maintainer)

1. Push session images to `images.canfar.net/astroai/` with a version tag (e.g. `26.06`).
2. Register **Contributed** types for `webterm`, `vscode`, `marimo` — port **5000**.
3. Register **Notebook** type for `notebook` — port **8888**. (Optional: ask CANFAR platform ops for the launch override above so `startup-notebook.sh` runs.)
4. Do not expose `base` as an interactive session.
5. Document the tag policy for users (monthly `YY.MM`; avoid `latest` in production).

## Local smoke test

Contributed (webterm):

```bash
make build/webterm
./scripts/test-local.sh webterm 5000
./scripts/test-local.sh webterm --verify-only   # CADC/PATH checks without starting ttyd
```

Notebook:

```bash
make build/notebook
./scripts/test-local.sh notebook 8888
# simulates: /skaha/startup.sh <session-id> on port 8888
```

## Post-push verification on CANFAR (headless)

After pushing to Harbor, run a headless Skaha session that executes `canfar-verify.sh` inside the image. Requires the [canfar CLI](https://opencadc.github.io/canfar/) authenticated (`canfar auth login`). Harbor pull auth is **not** required when the `astroai` project is public (see [Harbor registry](#harbor-registry-public-project)).

```bash
make push/base TAG=26.06
make test-canfar IMAGE=base TAG=26.06

# Or directly:
./scripts/test-canfar.sh webterm 26.06
```

The script creates a headless session, waits for it to finish, prints logs (`canfar logs`), and checks for `All checks passed.` Session cleanup is automatic.

Verify checks include CADC/CANFAR CLIs (`canfar`, `cadcget`, `cadc-tap`, `vcp`) on **login shells** (`bash -l`), matching webterm tmux behaviour.

## Diagnostic tool (`astroai-debug`)

Every session image includes `astroai-debug`, a comprehensive diagnostic tool that produces a timestamped snapshot of the container's runtime state. Operators can use it to inspect live containers, triage user issues, or gather fleet-wide health data.

### What it covers

The report has 10 sections:

| Section | Details for operators |
|---------|----------------------|
| Session | Home, PWD, scratch mount status + free space, TMPDIR, shell PID, system uptime |
| Profile | `ASTROAI_PROFILE_LOADED` guard, PATH layout, uv/pixi/cache directory locations |
| GPU | `nvidia-smi` query (GPU index, driver, VRAM, temp, utilization) + GPU process listing |
| Disk | `/scratch` and `HOME` `df`, top 10 directories in HOME by size, top 10 directories on /scratch |
| Tools | Version check for pre-installed dev, file, and CADC tools |
| Project | Pixi/uv project detection, lockfile size, `.pixi`/`.venv` directory size |
| Network | HTTPS reachability to pypi.org, github.com, conda.anaconda.org, files.pythonhosted.org |
| Environment | Key env vars (PATH, HOME, XDG, UV, PIXI, CUDA, etc.) with tokens/keys redacted |
| Processes | Top 10 processes by CPU (pid, user, %cpu, %mem, command) |
| CVMFS | `/cvmfs/soft.computecanada.ca` mount status with lazy-mount hint |

### Running inside a container

```bash
# From the container shell (as the user)
astroai-debug                     # prints + saves to ~/.astroai/debug-<timestamp>.log
astroai-debug --stdout            # print only (no file saved)

# As an operator (inspect via docker exec or kubectl exec)
docker exec <container> astroai-debug --stdout
kubectl exec <pod> -- astroai-debug --stdout
```

### Operator use cases

**Triage user reports:** Ask the user to run `astroai-debug` and share the log (`cat ~/.astroai/debug-*.log`). The report answers the most common support questions in one file — is /scratch mounted? Is the profile sourced? Are tools present? Is the network reachable?

**Fleet health:** Run `astroai-debug --stdout` across all running containers to spot patterns — stale sessions with zero scratch usage, quota-pressure nodes, or CVMFS mount failures.

**Image smoke test:** During image development, run `astroai-debug --stdout` inside the test container after `test-local.sh` to confirm all pre-installed tools are present, the profile is sourced, and CVMFS is reachable.

### Log location

By default, reports save to `~/.astroai/debug-<YYYYMMDDTHHMMSSZ>.log` on `/arc` (persists across sessions). The `--file` flag saves to a custom path.

## AI coding tools (`astroai-install`)

Session images ship a curated set of dev CLIs (`gh`, `rg`, `fd`, `bat`, `fzf`, `delta`, `tldr`) but do **not** bundle AI agent binaries or Node.js — those change too fast to pin in an image. Users install them on-demand with `astroai-install`, which handles the right installer per tool and verifies each install. All tools land in `~/.local/bin` on `/arc` (persistent across sessions).

### Available tools

| Tool | Command | Installer | Node? |
|------|---------|-----------|-------|
| Cursor Agent | `agent` | curl script | No |
| Claude Code | `claude` | curl script | No |
| Antigravity (Google) | `agy` | curl script | No |
| OpenCode | `opencode` | curl script | No |
| Codex CLI (OpenAI) | `codex` | `gh release download` | No |
| Freebuff | `freebuff` | npm | **Yes** |
| Aider | `aider` | `uv tool install` | No |

The table reflects `astroai-install`'s chosen install path. Some tools have alternative install methods (e.g., Codex also has an npm package, OpenCode offers an npm option) — USAGE.md covers those for users who install manually.

Six of seven tools install without Node. Codex uses `gh release download` (requires `gh auth login`). Freebuff is the only npm-only tool — the script detects the missing `npm` and guides the user to install Node via pixi or CVMFS.

### Pre-seeding in the base image

**Recommendation:** Pre-seed nothing by default. Tools install once to `/arc` via `astroai-install` and persist; baking agents adds ~300–500 MB and freezes weekly-moving binaries at build time. If a site needs zero-setup, pre-seed 2–3 audited tools in `dockerfiles/base/Dockerfile` and document that `astroai-install` still fetches the latest version.

### Freebuff and Node.js

Freebuff is npm-only. Operators have three options:

1. **Don't pre-seed it in `base`** — users run `astroai-install node` once (pixi global → `~/.local/bin`, persists on `/arc`), then `astroai-install freebuff`.
2. **Add Node to the base image** (`apt install nodejs npm` — ~200 MB). This lets `npm install -g freebuff` work out of the box. Update USAGE.md's "Not in the image" list if you do this.
3. **Create a separate "full" image** (`astroai/full`) with Node.js LTS pre-installed — see `dockerfiles/full/Dockerfile`. Users who need npm CLIs without setup can launch `full` instead of `base`; everyone else runs `astroai-install node` once on `/arc`.

### Operator implications

**Support:** Most AI tool issues are auth-related (expired tokens, wrong API key) — not install problems. `astroai-install` prints first-run instructions after each install (e.g., `Run: claude` for sign-in). Point users at those.

**Common issues:**
- `gh release download` fails for codex → `gh auth login` not run, or GitHub token expired
- `npm not found` for freebuff → user needs `pixi add nodejs` or `module load nodejs`
- Binary not on PATH → user needs `hash -r` or a new shell after install
- Tool update → each tool has its own update: `agent update`, `agy update`, `claude` auto-updates, `uv tool upgrade aider-chat`

**Security:** Five of seven tools install via `curl | bash`. This is the vendor-recommended method and standard industry practice for CLI tools. Operators concerned about supply chain risk can:
- Pre-seed audited versions in the Dockerfile (binary verified at build time)
- Block curl-based installers at the network level (but this also disables `astroai-install`)

**Audit trail:** `astroai-debug` checks 19 pre-installed system tools but does not list user-installed AI agents. If fleet-wide AI tool tracking is needed, consider adding a separate audit script (`ls ~/.local/bin/agent ~/.local/bin/claude ~/.local/bin/agy ~/.local/bin/opencode ~/.local/bin/codex ~/.local/bin/freebuff ~/.local/bin/aider`).

## Quota monitoring

Session images include built-in quota awareness for `/arc/home` (personal) and `/arc/projects/<group>/` (team) storage. Quota checks fire at three touchpoints and use three threshold levels.

### Where quotas are checked

| Touchpoint | When | What it does |
|-----------|------|-------------|
| Session start (`common-init.sh`) | Every new session | Runs `astroai_quota_startup_check` — silently probes home and project quota via `df`; prints warnings only if a threshold is crossed |
| `astroai-status` | User runs it manually | Shows quota-aware disk lines with usage percentage and alert level for scratch, home, and current project |
| `astroai-home-usage` | User runs it manually | Opens with a quota overview for home and all accessible projects, plus a percentage summary |

### Threshold levels

| Level | Threshold | Message | Action |
|-------|-----------|---------|--------|
| Monitor | ≥ 80% | `⚠ monitor (astroai-home-usage)` | No action needed — user sees a heads-up |
| High | ≥ 90% | `⚠ high — prune soon (astroai-cache-prune --all-safe)` | Encourage cache pruning |
| Critical | ≥ 95% | `⚠ CRITICAL — near quota limit` | Immediate pruning required; env save may fail |

### How quota is measured

```bash
# Per-path df query (no external API dependency)
df /arc/home/user | awk 'NR>1 {used=$3; size=$2; printf "%.0f", (used/size)*100}'
```

Uses standard `df` on the CephFS mount — works without `quota` command or platform API access.

### Project quota detection

At session start, `astroai_quota_startup_check` walks up from the current working directory (`/scratch/<project>`) to find the nearest `/arc/projects/<group>/` ancestor and checks its quota. This catches team projects even when the user is several directories deep in `/scratch`.

### Operator implications

**Capacity planning:** Monitor quota warnings across the fleet to identify groups approaching their `/arc` allocation before users hit write errors.

**Support:** When a user reports `env-save` failures or `No space left on device` errors, check:
1. `astroai-debug` Disk section — shows `/scratch` and `/arc/home` free space
2. `astroai-home-usage` — breaks down what's consuming the user's quota
3. `astroai-cache-prune --all-safe` — clears pip/uv/npm/pixi caches

**Quota visibility is passive:** The checks read usage percentages from the filesystem — they do not enforce limits or block writes. The platform controls actual quota enforcement at the CephFS level.

## User data lifecycle

Session images work on `/scratch` (fast local SSD, wiped at session end) while persistent storage lives on `/arc` (CephFS, permanent). Two commands bridge these tiers and let users persist their work before closing a session.

### `astroai-session-archive` — closing a session safely

Users run this before ending a session. It performs three steps:

1. **Git push** — pushes the current branch. Warns if uncommitted changes exist (the push still runs, but uncommitted work is called out).
2. **Environment save** — auto-detects pixi/uv projects and runs `astroai-env-save`. Accepts `--name <custom>` for team-friendly save names.
3. **Summary** — reports what was archived and whether anything was missed:
   - `git push: done` or `git push: skipped`
   - `env save: done (<name>)` or `env save: skipped`
   - `uncommitted changes exist — not archived` (if applicable)

If the user is not in a git repo or no pixi/uv project is detected, the script tells them what's missing and how to set it up.

The summary closes with a `/scratch` ephemeral warning and contextual advice based on what was successfully archived.

### `astroai-data-stage` / `astroai-data-sync` — moving data between tiers

These are rsync wrappers for the two directions of data movement:

| Command | Direction | Default target |
|---------|-----------|---------------|
| `astroai-data-stage <src> [dst]` | Persistent → `/scratch` | `/scratch/<basename of src>` |
| `astroai-data-sync <src> <dst>` | `/scratch` → Persistent | *(required)* |

- **Stage** shows source size and asks before overwriting an existing target.
- **Sync** shows source size plus destination free space, and warns if the source is not on `/scratch`.
- Both use `rsync -avh --progress` for visible transfer progress.

### Typical data lifecycle

```
Session start
    │
    ├── astroai-data-stage /arc/projects/mygroup/data.fits   ← stage data to fast SSD
    │
    ▼
Active work (on /scratch)
    │
    ├── astroai-data-sync /scratch/results/ /arc/projects/mygroup/results/   ← sync results back
    ├── git commit -am "results"                            ← commit before archiving
    │
    ▼
astroai-session-archive                                    ← push code + save env + summary
    │
    ▼
Session ends → /scratch wiped
```

### Operator implications

**Support — when a user reports lost work after session end:**

| Was it... | Check | Recovery path |
|-----------|-------|--------------|
| Code | Git remote | If pushed, clone back. If not pushed, data was on `/scratch` — unrecoverable. |
| Environment | `~/.astroai/saves/` or `/arc/projects/<group>/env-saves/` | Resume with `astroai-env-resume` |
| Data | `/arc/projects/<group>/` | If synced, data is safe. If still on `/scratch`, unrecoverable. |

**Common failure modes operators can help with:**

- **Git push fails** — no remote configured, or GitHub auth token expired. Guide user through `gh auth login` or `git remote add origin`.
- **Env save fails** — quota full. Check `astroai-home-usage`, recommend `astroai-cache-prune --all-safe`, retry save.
- **Data sync not run** — `/scratch` is unrecoverable after session expiry. Emphasize this in onboarding; the `astroai-session-archive` summary reminds users but doesn't run `astroai-data-sync` automatically (it doesn't know which data to sync).

**Capacity planning:**

- Data staged to `/scratch` consumes local SSD on the compute node — large datasets can exhaust node-local storage.
- Data synced to `/arc/projects` increases project quota consumption. The quota monitoring system (see above) catches this at 80/90/95% thresholds.
- `astroai-data-sync` shows destination free space before syncing, giving users a chance to abort if the target is near quota.

**Platform safety note:** The platform does not trigger `astroai-session-archive` or `astroai-data-sync` automatically at session end. `/scratch` is wiped with no recovery path. Operators may want to:
- Document this prominently in session onboarding materials.
- Consider a platform-side pre-stop hook that sends users a `/scratch` reminder (but note: automating `rsync` runs or `git push` in a shutdown hook carries risk — partial transfers, stale credentials, quota exhaustion mid-sync). The current design keeps these decisions user-initiated.

## Usage docs for users

Point users to [USAGE.md](USAGE.md) (also at `/opt/astroai/USAGE.md` inside sessions).
