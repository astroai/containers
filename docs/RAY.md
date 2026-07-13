# Distributed Ray on CANFAR

## Product direction (slim)

AstroAI does **not** maintain a custom Ray console as a product.

| Prefer | Avoid |
|--------|--------|
| Stock **Ray Dashboard** (`/dashboard/`) | Growing the FastAPI control panel |
| `scripts/ray-launch.sh` + `canfar` | New UI workflows in `ray/manager/ui.py` |
| ``canfar create` + stock Dashboard` | Separate CUDA/ML Ray images |
| Student notebook `/opt/astroai/notebooks/ray_train.ipynb` | Prefect / new orchestration UIs |

The existing manager UI is **frozen** (`ray/manager/FROZEN.md`) so current E2E tests keep working while we steer users to Dashboard + scripts.

User-owned Ray clusters: a **contributed `ray-manager` session** (port 5000) launches **headless `ray-worker` sessions** over pod networking. One worker image serves **CPU and GPU** nodes — request GPUs per worker in the UI or API (`gpus=N`); CANFAR schedules GPU nodes and the worker entrypoint verifies `nvidia-smi`. ML/CUDA stacks belong in user pixi/uv projects (same as other AstroAI images). Persistent state uses **`/arc/home/<user>/`** (or **`/arc/projects/<group>/`** for team workspaces) — never the `/arc` mount root. **`/scratch`** is required for spill/temp on all nodes.

## Images

| Image | Skaha type | Portal |
|-------|------------|--------|
| `ray-manager` | Contributed | Register — users launch this |
| `ray-worker` | Headless | **Do not register** — manager launches workers |

`ray-base` is build-only (extends `base` with a Python 3.12 Ray venv).

## Build and test

```bash
make build-ray BUILD_TAG=26.06
make test-ray                              # local: 1-worker, 2-worker + recovery
make push-ray TAG=26.06
make test-canfar-ray TAG=26.07             # CANFAR: 2-worker cluster lifecycle
make test-canfar-ray-gpu TAG=26.07         # CANFAR: 1 GPU worker (production)
# If headless probe/workers hang Pending: see docs/HEADLESS_PENDING.md
# CANFAR_RAY_SKIP_PREFLIGHT=1 make test-canfar-ray TAG=26.07
# Launch managers with ≥8GiB when exercising Ray Jobs (4GiB OOMs the dashboard).
```

Ray layers use the **same bake `TAG` as `base`** — no separate `BASE_TAG` pin.

## CANFAR authentication

The manager launches workers with the **`canfar` Python client**. Run once from webterm/vscode:

```bash
canfar login
```

(`canfar auth login` is a deprecated alias — prefer `canfar login`.)

Credentials persist on **`/arc/home/<you>/`** as `~/.canfar/config.yaml` (and optionally `~/.ssl/cadcproxy.pem`). Ray-manager sessions reuse the same home volume.

For headless worker launches, registry pull auth must also be configured (same file or env):

```bash
canfar config set registry.url https://images.canfar.net
canfar config set registry.username <harbor-user>
canfar config set registry.secret <harbor-cli-secret>
```

Maintainer smoke tests load docker login credentials and persist them to `/arc/home` via a short headless bootstrap session before creating the manager (`scripts/test-canfar-ray.sh`).

## Network preflight

Preflight launches a **headless probe session** to verify pod-to-pod TCP on Ray ports (6379–6381). This requires CANFAR/Skaha to allow traffic between a user's contributed manager and their headless workers. If the probe stays **Pending** with no Start Time, that is a **headless scheduling** hang — see [HEADLESS_PENDING.md](HEADLESS_PENDING.md). If all `worker->manager` checks fail while the manager is healthy, that is usually **platform session-to-session network isolation** — see [ray-build-plan.md](ray-build-plan.md) §18. Worker logs showing `ERROR: cannot reach Ray head at <manager-ip>:6379` confirm the same block after the worker starts.

Maintainer tests can set `CANFAR_RAY_SKIP_PREFLIGHT=1` to exercise UI/auth without preflight when staging blocks cross-session TCP.

## Web UI (frozen control panel + stock Dashboard)

Contributed **`ray-manager`** serves a browser UI on port **5000** (same as webterm/vscode).

| Surface | Purpose |
|---------|---------|
| `/` | Thin CANFAR control panel — auth, preflight, create/stop cluster, worker table |
| `/dashboard/` | Official **Ray Dashboard** (jobs, actors, nodes, metrics, logs), reverse-proxied from `127.0.0.1:8265` |
| `/actions/*` | Form POSTs for cluster lifecycle (redirect + flash) |
| `/api/v1/*` | JSON automation |

The Ray head starts with `--include-dashboard=true` bound to **localhost only**. CANFAR ingress exposes only port 5000 under `/session/contrib/<session-id>/` (prefix stripped before the container). The manager therefore emits browser links as `/session/contrib/<id>/dashboard/` (from `skaha_sessionid`) so **Open Ray Dashboard** stays inside the session URL — never bare `https://workloads.canfar.net/dashboard/`. Always open the dashboard with a trailing slash.

After launch, open the session connect URL and verify:

- CANFAR auth line shows **Authenticated**
- Programmatic Jobs clients on this pod use **`ASTROAI_RAY_JOBS_ADDRESS`**
  (`http://127.0.0.1:8265`, set by `startup-ray-manager.sh`). Browsers use
  `connectURL/dashboard/` — do not invent hostnames like `ray-manager:8265`.
- **Open Ray Dashboard** works (jobs/nodes UI)
- **Run network preflight** before first cluster create
- Worker table shows session IDs, phases, and **Retry** for failed workers

Local smoke: `./scripts/test-ray-ui-local.sh` (included in `make test-ray`). On CANFAR: `make test-canfar-ray TAG=26.06` checks HTML + API after push.

## Cluster workflow (Milestone C)

1. **Run network preflight** — verifies pod-to-pod TCP for Ray ports
2. **Create cluster** — specify worker count, CPU/RAM, **GPUs per worker**, min joined, partial-start policy
3. **Use Ray** — connect with `ray.init(address="auto")` from the manager or your code
4. **Stop cluster** — destroys all worker sessions and marks cluster `Stopped`

Partial-start policies:

| Policy | Behavior |
|--------|----------|
| `accept_partial` | Proceed when `min_joined` workers are healthy (cluster phase `Degraded`) |
| `fail_and_cleanup` | Destroy workers and fail if minimum not met |
| `continue_waiting` | Poll until timeout |

State persists at `~/.astroai/ray/clusters/<cluster-id>/state.json`. Headless worker stdout/stderr is archived under `workers/<session-id>.log` in the same directory (survives CANFAR session deletion). Fetch via `GET /api/v1/workers/{session_id}/logs` or the **logs** link in the UI. On manager restart, **Reconcile state** (or automatic startup reconcile) refreshes CANFAR + Ray membership.

## Manager API

| Endpoint | Purpose |
|----------|---------|
| `GET /api/v1/auth/status` | CANFAR credential check |
| `POST /api/v1/preflight/run` | Network preflight (`?async=1` returns 202 immediately; poll `GET /api/v1/status`) |
| `POST /api/v1/cluster/create` | Launch N workers (`?async=1` avoids ingress timeout; poll status) |
| `POST /api/v1/cluster/stop` | Stop cluster and destroy workers |
| `POST /api/v1/cluster/reconcile` | Refresh CANFAR/Ray state |
| `POST /api/v1/cluster/clean-orphans` | Destroy untracked worker sessions |
| `POST /api/v1/workers/{id}/retry` | Retry a failed worker |
| `GET /api/v1/status` | Full cluster JSON |

## Layout

```
ray/manager/           # FastAPI + cluster lifecycle
scripts/test-ray-cluster-local.sh
examples/ray/
```

Full spec: [ray-build-plan.md](ray-build-plan.md).

## Status

| Milestone | Scope | Status |
|-----------|--------|--------|
| A | Local manager + worker join | Done |
| B | CANFAR auth, preflight, worker via API | Done |
| C | Multi-worker cluster, stop, reconcile, recovery | Done |
| D | Astronomy workload validation | Planned |
| E | GPU worker validation (single `ray-worker` image) | Done |
