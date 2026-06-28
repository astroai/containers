# Distributed Ray on CANFAR

User-owned Ray clusters: a **contributed `ray-manager` session** (port 5000) launches **headless `ray-worker-cpu` sessions** over pod networking. Same storage model as other AstroAI images (`/arc`, `/scratch`).

## Images

| Image | Skaha type | Portal |
|-------|------------|--------|
| `ray-manager` | Contributed | Register — users launch this |
| `ray-worker-cpu` | Headless | **Do not register** — manager launches workers |

`ray-base` is build-only (extends `base` with a Python 3.12 Ray venv).

## Build and test

```bash
make build-ray BUILD_TAG=26.06
make test-ray                              # local: 1-worker, 2-worker + recovery
make push-ray TAG=26.06
make test-canfar-ray TAG=26.06             # CANFAR: 2-worker cluster lifecycle
```

Ray layers use the **same bake `TAG` as `base`** — no separate `BASE_TAG` pin.

## CANFAR authentication

The manager launches workers with the **`canfar` Python client**. Run once from webterm/vscode:

```bash
canfar auth login
```

Credentials persist on **`/arc/home/<you>/`** as `~/.canfar/config.yaml` (and optionally `~/.ssl/cadcproxy.pem`). Ray-manager sessions reuse the same home volume.

## Web UI

Contributed **`ray-manager`** serves a browser UI on port **5000** (same as webterm/vscode). Forms POST to `/actions/*` and redirect back with flash messages; JSON automation uses `/api/v1/*`.

After launch, open the session connect URL and verify:

- CANFAR auth line shows **Authenticated**
- **Run network preflight** before first cluster create
- Worker table shows session IDs, phases, and **Retry** for failed workers

Local smoke: `./scripts/test-ray-ui-local.sh` (included in `make test-ray`). On CANFAR: `make test-canfar-ray TAG=26.06` checks HTML + API after push.

## Cluster workflow (Milestone C)

1. **Run network preflight** — verifies pod-to-pod TCP for Ray ports
2. **Create cluster** — specify worker count, CPU/RAM, min joined, partial-start policy
3. **Use Ray** — connect with `ray.init(address="auto")` from the manager or your code
4. **Stop cluster** — destroys all worker sessions and marks cluster `Stopped`

Partial-start policies:

| Policy | Behavior |
|--------|----------|
| `accept_partial` | Proceed when `min_joined` workers are healthy (cluster phase `Degraded`) |
| `fail_and_cleanup` | Destroy workers and fail if minimum not met |
| `continue_waiting` | Poll until timeout |

State persists at `~/.canfar-ray/clusters/<cluster-id>/state.json`. On manager restart, **Reconcile state** (or automatic startup reconcile) refreshes CANFAR + Ray membership.

## Manager API

| Endpoint | Purpose |
|----------|---------|
| `GET /api/v1/auth/status` | CANFAR credential check |
| `POST /api/v1/preflight/run` | Network preflight |
| `POST /api/v1/cluster/create` | Launch N workers (`worker_count`, policy, resources) |
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
