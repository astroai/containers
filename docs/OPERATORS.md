# Operator guide

Register and publish AstroAI images on the CANFAR Science Platform.

## Images and session types

| Image | Harbor path | Skaha session type | Port | User-facing |
|-------|-------------|-------------------|------|-------------|
| `base` | `images.canfar.net/astroai/base:<tag>` | *(not launched)* | — | Headless parent only |
| `webterm` | `images.canfar.net/astroai/webterm:<tag>` | **Contributed** | 5000 | Browser terminal |
| `vscode` | `images.canfar.net/astroai/vscode:<tag>` | **Contributed** | 5000 | Browser IDE |
| `notebook` | `images.canfar.net/astroai/notebook:<tag>` | **Notebook** | 8888 | JupyterLab |
| `marimo` | `images.canfar.net/astroai/marimo:<tag>` | **Contributed** | 5000 | Reactive notebooks |

Each image carries `io.canfar.skaha.session.type` in its OCI labels (`headless`, `contributed`, or `notebook`) for Harbor inventory.

Build and push:

```bash
make build-all
make push/notebook TAG=26.06
make push/webterm TAG=26.06
```

Do **not** register `base` as a Science Portal session — it is the shared parent layer.

## Contributed sessions (webterm, vscode, marimo)

Register as **Contributed** in the Science Portal.

- `skaha_sessionid` is set in the container environment
- Reverse-proxy path: `/session/contrib/<session-id>/`
- Container listens on port **5000**
- Image entrypoint: `/skaha/startup.sh` → `/cadc/startup-<image>.sh`
- Platform does not override the container command

## Notebook sessions (notebook image only)

Register `images.canfar.net/astroai/notebook:<tag>` as a **Notebook** session type.

- Session ID is passed as the **first argument** to `/skaha/startup.sh`
- `JUPYTER_TOKEN` is also set to the session ID (platform default)
- Reverse-proxy path: `/session/notebook/<session-id>/`
- Container listens on port **8888**
- Jupyter `base_url`: `session/notebook/<session-id>` (matches platform convention)

### Launch template override (required)

The stock Skaha notebook job runs `/skaha-system/start-jupyterlab.sh` from a ConfigMap. That script skips AstroAI session setup (`common-init`, `/scratch` cwd, cache dirs).

**Override the container command** for AstroAI notebook images:

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

Remove or replace the `start-jupyterlab` ConfigMap volume mount when using this override.

## Image entrypoints

| Image | `/skaha/startup.sh` | `CMD` |
|-------|---------------------|-------|
| `webterm` | → `startup-webterm.sh` | `/cadc/startup-webterm.sh` |
| `vscode` | → `startup-vscode.sh` | `/cadc/startup-vscode.sh` |
| `notebook` | → `startup-notebook.sh "$@"` | `/skaha/startup.sh` |
| `marimo` | → `startup-marimo.sh` | `/cadc/startup-marimo.sh` |

Contributed images work with either `CMD` or `/skaha/startup.sh`. Notebook images expect the session ID as `$1`.

## Science Portal checklist

1. Push session images to `images.canfar.net/astroai/` with a version tag (e.g. `26.06`).
2. Register **Contributed** types for `webterm`, `vscode`, `marimo` — port **5000**.
3. Register **Notebook** type for `notebook` — port **8888**, with launch override above.
4. Do not expose `base` as an interactive session.
5. Document the tag policy for users (monthly `YY.MM`; avoid `latest` in production).

## Local smoke test

Contributed (webterm):

```bash
make build/webterm
./scripts/test-local.sh webterm 5000
```

Notebook:

```bash
make build/notebook
./scripts/test-local.sh notebook 8888
# simulates: /skaha/startup.sh <session-id> on port 8888
```

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
| Tools | Version check for 19 pre-installed tools (git, gh, uv, pixi, jq, rg, fd, bat, etc.) |
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
