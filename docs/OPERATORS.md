# Publishing & registration guide

For **AstroAI project maintainers** who build, push, and register `images.canfar.net/astroai/*` session images on the CANFAR Science Platform.

**Not for CANFAR platform admins.** Skaha deployment, Helm charts, and launch scripts live in [opencadc/science-platform](https://github.com/opencadc/science-platform). This repo has **no write access** there — only image build/push and Science Portal registration within the `astroai` Harbor project. Platform changes are **feature requests or bug reports** to the CANFAR/science-platform team.

| Role | Scope | Where |
|------|--------|--------|
| **AstroAI maintainer** (this doc) | Build, push, register images; smoke-test on CANFAR | containers, Harbor `astroai/`, Science Portal |
| **CANFAR platform admin** | Skaha Helm, launch scripts, ingress, cluster config | opencadc/science-platform |

## Images and session types

| Image | Harbor path | Skaha session type | Port | User-facing |
|-------|-------------|-------------------|------|-------------|
| `base` | `images.canfar.net/astroai/base:<tag>` | *(not launched)* | — | Headless parent only |
| `webterm` | `images.canfar.net/astroai/webterm:<tag>` | **Contributed** | 5000 | Browser terminal |
| `vscode` | `images.canfar.net/astroai/vscode:<tag>` | **Contributed** | 5000 | Browser IDE |
| `notebook` | `images.canfar.net/astroai/notebook:<tag>` | **Notebook** | 8888 | JupyterLab |
| `marimo` | `images.canfar.net/astroai/marimo:<tag>` | **Contributed** | 5000 | Reactive notebooks |
| `ray-manager` | `images.canfar.net/astroai/ray-manager:<tag>` | **Contributed** | 5000 | Ray cluster control UI |
| `ray-worker` | `images.canfar.net/astroai/ray-worker:<tag>` | **Headless** | — | Ray worker CPU or GPU (manager-launched) |

Each image carries `io.canfar.skaha.session.type` in its OCI labels (`headless`, `contributed`, or `notebook`) for Harbor inventory.

**Ray:** register **`ray-manager`** only in the Science Portal. Do **not** register `ray-worker` — workers are launched headlessly by the manager. See [RAY.md](RAY.md).

Users must run `canfar auth login` once from another AstroAI session so credentials persist under `/arc/home` (`~/.canfar/config.yaml`). Maintainers validate Ray with `make test-canfar-ray TAG=26.06` after push (UI smoke + 2-worker cluster). GPU: `make test-canfar-ray-gpu TAG=26.06` on production.

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
make build-all BUILD_TAG=26.06
make push-all TAG=26.06 BUILD_TAG=26.06   # base + webterm + notebook + vscode + marimo (+ :latest each)
make build-ray BUILD_TAG=26.06
make push-ray TAG=26.06 BUILD_TAG=26.06
```

`make push-all` includes **`push/base`** — each `push/<image>` publishes both `TAG` and **`latest`**.  
Do **not** rely on `make push-ray` alone for `base` (Ray parent only).  
`docker buildx bake --push` tags `base:${TAG}` only, not `latest`.

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

That script is **not in containers** — Jupyter `NotebookApp → ServerApp` migration warnings, `root_dir=/`, and missing `common-init` on notebook sessions are **CANFAR platform behaviour** until the science-platform team changes `launch-notebook.yaml` or modernizes `start-jupyterlab.sh`.

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

| Source | Examples | Fixable in containers? |
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

## Diagnostic tool (`canfar-lab doctor`)

Every session image includes `canfar-lab doctor`, which prints resolved session
paths, cache locations, tool availability on PATH, home quota usage, and
**`canfar auth show`** when the `canfar` CLI is installed.

### What it covers

| Field / section | Details for operators |
|-----------------|----------------------|
| Paths | `work_dir`, `scratch_dir`, `save_dir`, `user_bin`, `runtime_root`, pixi/uv cache dirs |
| Tools | Whether `git`, `gh`, `pixi`, `uv`, `canfar`, `rsync`, `jupyter`, … are on PATH |
| CANFAR | `canfar auth show` when logged in (JSON key: `canfar_auth` on `canfar-lab doctor --json`) |
| Quota | Home directory usage percentage |

For quotas, home breakdown, team projects (access/ACL/GMS/vault), **`canfar ps`**, and top CPU processes, use
**`canfar-lab status`** (`canfar-lab status --json` for scripts).

### Running inside a container

```bash
# From the container shell (as the user)
canfar-lab doctor
canfar-lab doctor --json

# As an operator (inspect via docker exec or kubectl exec)
docker exec <container> canfar-lab doctor --json
kubectl exec <pod> -- canfar-lab doctor --json
```

### Operator use cases

**Triage user reports:** Ask the user to run `canfar-lab doctor --json` (or
`canfar-lab status --json`) and share the output. This confirms resolved paths,
tool presence, and **`canfar auth show`** health.

For a quick CANFAR platform view, `canfar-lab status` also prints **`canfar auth show`** and **`canfar ps`**.

**Fleet health:** Run `canfar-lab doctor --json` across running containers to spot missing tools or auth failures.

**Image smoke test:** During image development, run `canfar-lab doctor` inside the test container after `test-local.sh` to confirm pre-installed tools are on PATH.

## AI coding tools (`canfar-lab agent install`)

Session images ship a curated set of dev CLIs (`gh`, `rg`, `fd`, `bat`, `fzf`, `delta`, `tldr`) but do **not** bundle AI agent binaries or Node.js — those change too fast to pin in an image. Users install them on-demand with `canfar-lab agent install`, which handles the right installer per tool and verifies each install. Binaries land in **`$CANFAR_LAB_BIN_DIR`** (scratch `.local/bin` by default; team/home fallback when scratch is absent).

### Available tools

| Tool | Command | Installer | Node? |
|------|---------|-----------|-------|
| Cursor Agent | `agent` | curl script | No |
| Claude Code | `claude` | curl script | No |
| Antigravity CLI (replaced Gemini CLI) | `agy` | curl script | No |
| OpenCode | `opencode` | curl script | No |
| Codex CLI (OpenAI) | `codex` | `gh release download` | No |
| GitHub Copilot CLI | `copilot` | curl script | No |
| Goose | `goose` | curl script | No |
| Pi Coding Agent | `pi` | npm | **Yes** |
| CodeWhale | `codewhale` | npm | **Yes** |
| Swival | `swival` | `uv tool install` | No |
| Freebuff | `freebuff` | npm | **Yes** |

The table reflects `canfar-lab agent install`'s chosen install path. Some tools have alternative install methods (e.g., Codex also has an npm package, OpenCode offers an npm option) — USAGE.md covers those for users who install manually.

Seven of eleven tools install without Node. Codex uses `gh release download` (requires `gh auth login`). Swival uses `uv tool install`. Pi, CodeWhale, and Freebuff need npm — the script detects a missing `npm` and guides the user to install Node via pixi or CVMFS.

### Pre-seeding in the base image

**Recommendation:** Pre-seed nothing by default. Tools install once to `/arc` via `canfar-lab agent install` and persist; baking agents adds ~300–500 MB and freezes weekly-moving binaries at build time. If a site needs zero-setup, pre-seed 2–3 audited tools in `dockerfiles/base/Dockerfile` and document that `canfar-lab agent install` still fetches the latest version.

### npm-based agents and Node.js

Pi, CodeWhale, and Freebuff are npm-only. Users run `canfar-lab agent install node` once
(pixi global → `~/.local/bin`, persists on `/arc`), then install the npm-based
agents. Alternatives: `pixi add nodejs` under **`TMP_SRC_DIR`**, or CVMFS
`module load nodejs`.

### Operator implications

**Support:** Most AI tool issues are auth-related (expired tokens, wrong API key) — not install problems. `canfar-lab agent install` prints first-run instructions after each install (e.g., `Run: claude` for sign-in). Point users at those.

**Common issues:**
- `gh release download` fails for codex → `gh auth login` not run, or GitHub token expired
- `npm not found` for pi/codewhale/freebuff → user needs `canfar-lab agent install node`, `pixi add nodejs`, or `module load nodejs`
- Binary not on PATH → user needs `hash -r` or a new shell after install
- Tool update → each tool has its own update: Cursor Agent `agent update`, Antigravity `agy update`, Claude Code auto-updates, `uv tool upgrade swival`, npm globals for pi/codewhale/freebuff

**Security:** Seven of eleven tools install via `curl | bash`. This is the vendor-recommended method and standard industry practice for CLI tools. Operators concerned about supply chain risk can:
- Pre-seed audited versions in the Dockerfile (binary verified at build time)
- Block curl-based installers at the network level (but this also disables `canfar-lab agent install`)

**Audit trail:** `canfar-lab doctor` checks **9** pre-installed tools (`git`, `gh`, `pixi`, `uv`, `jq`, `rg`, `canfar`, `rsync`, `jupyter`) but does not list user-installed AI agents. If fleet-wide AI tool tracking is needed, consider a separate audit script listing **`$CANFAR_LAB_BIN_DIR`** (e.g. `agent`, `claude`, `codex`, …).

## Quota monitoring

Session images include built-in quota awareness for `/arc/home` (personal) and `/arc/projects/<group>/` (team) storage. Quota checks fire at three touchpoints and use three threshold levels.

### Where quotas are checked

| Touchpoint | When | What it does |
|-----------|------|-------------|
| Session start (`common-init.sh`) | Every new session | Runs `astroai_quota_startup_check` — silently probes home and project quota via `df`; prints warnings only if a threshold is crossed |
| `canfar-lab status` | User runs it manually | Quota overview (POSIX + optional vos vault), team projects (access/ACL/GMS/vault), home breakdown, **`canfar auth show`**, **`canfar ps`**, top processes |

### Threshold levels

| Level | Threshold | Message | Action |
|-------|-----------|---------|--------|
| Monitor | ≥ 80% | `⚠ monitor (canfar-lab status)` | No action needed — user sees a heads-up |
| High | ≥ 90% | `⚠ high — prune soon (canfar-lab clean home --all-safe)` | Encourage home cleanup |
| Critical | ≥ 95% | `⚠ CRITICAL — near quota limit` | Immediate pruning required; env save may fail |

### How quota is measured

```bash
# Per-path df query (no external API dependency)
df /arc/home/user | awk 'NR>1 {used=$3; size=$2; printf "%.0f", (used/size)*100}'
```

Uses standard `df` on the CephFS mount for home and `/arc/projects/*`. When CADC auth
and `vos` are available, **`canfar-lab status --json`** also reports VOSpace **vault**
quotas and read/write groups per container (`vault` key).

### Project quota detection

At session start, `astroai_quota_startup_check` walks up from the current working directory (usually under **`TMP_SRC_DIR`**) to find the nearest `/arc/projects/<group>/` ancestor and checks its quota.

### Operator implications

**Capacity planning:** Monitor quota warnings across the fleet to identify groups approaching their `/arc` allocation before users hit write errors.

**Support:** When a user reports `env-save` failures or `No space left on device` errors, check:
1. `canfar-lab doctor` Disk section — shows **`TMP_SRC_DIR`**, **`TMP_SCRATCH_DIR`**, and `/arc/home` free space
2. `canfar-lab status` — breaks down what's consuming the user's quota
3. `canfar-lab clean home --all-safe` — clears re-downloadable junk under `/arc/home`
4. `canfar-lab clean cache --all-safe` — clears scratch download caches if needed

**Quota visibility is passive:** The checks read usage percentages from the filesystem — they do not enforce limits or block writes. The platform controls actual quota enforcement at the CephFS level.

## User data lifecycle

Session images use **`TMP_SRC_DIR`** (default `/srcdir`) for code and **`TMP_SCRATCH_DIR`** (default `/scratch`) for staged data and download caches — both are fast local SSD, wiped at session end. Persistent storage lives on `/arc` (CephFS, permanent). Commands bridge these tiers and let users persist work before closing a session.

### `canfar-lab push` — closing a session safely

Users run this before ending a session. It performs three steps:

1. **Git push** — pushes the current branch. Warns if uncommitted changes exist (the push still runs, but uncommitted work is called out).
2. **Environment save** — auto-detects pixi/uv projects and runs `canfar-lab save`. Accepts `--name <custom>` for team-friendly save names.
3. **Summary** — reports what was archived and whether anything was missed:
   - `git push: done` or `git push: skipped`
   - `env save: done (<name>)` or `env save: skipped`
   - `uncommitted changes exist — not archived` (if applicable)

If the user is not in a git repo or no pixi/uv project is detected, the script tells them what's missing and how to set it up.

The summary closes with a **`TMP_SRC_DIR` ephemeral** warning and contextual advice based on what was successfully archived.

### `canfar-lab data stage` / `canfar-lab data sync` — moving data between tiers

These are rsync wrappers for the two directions of data movement:

| Command | Direction | Default target |
|---------|-----------|---------------|
| `canfar-lab data stage <src> [dst]` | Persistent → **`TMP_SCRATCH_DIR`** | `${TMP_SCRATCH_DIR}/<basename of src>` |
| `canfar-lab data sync <src> <dst>` | **`TMP_SCRATCH_DIR`** → Persistent | *(required)* |

- **Stage** shows source size and asks before overwriting an existing target.
- **Sync** shows source size plus destination free space, and warns if the source is not under **`TMP_SCRATCH_DIR`**.
- Both use `rsync -avh --progress` for visible transfer progress.

### Typical data lifecycle

```
Session start (cwd = TMP_SRC_DIR, default /srcdir)
    │
    ├── canfar-lab data stage /arc/projects/mygroup/data.fits   ← stage data to TMP_SCRATCH_DIR
    │
    ▼
Active work (code on TMP_SRC_DIR, datasets on TMP_SCRATCH_DIR)
    │
    ├── canfar-lab data sync ${TMP_SCRATCH_DIR}/results/ /arc/projects/mygroup/results/
    ├── git commit -am "results"
    │
    ▼
canfar-lab push                                    ← push code + save env + summary
    │
    ▼
Session ends → TMP_SRC_DIR and TMP_SCRATCH_DIR wiped
```

### Operator implications

**Support — when a user reports lost work after session end:**

| Was it... | Check | Recovery path |
|-----------|-------|--------------|
| Code | Git remote | If pushed, clone back. If not pushed, data was on `/scratch` — unrecoverable. |
| Environment | `~/.canfar/lab/saves/` or `/arc/projects/<group>/env-saves/` | Resume with `canfar-lab resume` |
| Data | `/arc/projects/<group>/` | If synced, data is safe. If still on `/scratch`, unrecoverable. |

**Common failure modes operators can help with:**

- **Git push fails** — no remote configured, or GitHub auth token expired. Guide user through `gh auth login` or `git remote add origin`.
- **Env save fails** — quota full. Check `canfar-lab status`, recommend `canfar-lab clean home --all-safe`, retry save.
- **Data sync not run** — `/scratch` is unrecoverable after session expiry. Emphasize this in onboarding; the `canfar-lab push` summary reminds users but doesn't run `canfar-lab data sync` automatically (it doesn't know which data to sync).

**Capacity planning:**

- Data staged to `/scratch` consumes local SSD on the compute node — large datasets can exhaust node-local storage.
- Data synced to `/arc/projects` increases project quota consumption. The quota monitoring system (see above) catches this at 80/90/95% thresholds.
- `canfar-lab data sync` shows destination free space before syncing, giving users a chance to abort if the target is near quota.

**Platform safety note:** The platform does not trigger `canfar-lab push` or `canfar-lab data sync` automatically at session end. `/scratch` is wiped with no recovery path. Operators may want to:
- Document this prominently in session onboarding materials.
- Consider a platform-side pre-stop hook that sends users a `/scratch` reminder (but note: automating `rsync` runs or `git push` in a shutdown hook carries risk — partial transfers, stale credentials, quota exhaustion mid-sync). The current design keeps these decisions user-initiated.

## Usage docs for users

Point users to [USAGE.md](USAGE.md) (also at `/opt/astroai/USAGE.md` inside sessions).
