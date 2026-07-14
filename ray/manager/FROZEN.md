# Custom Ray manager UI — frozen

The FastAPI control panel under `ray/manager/ui.py` is **frozen** for stability.

| Prefer | Scope |
|--------|--------|
| Stock **Ray Dashboard** at `/dashboard/` | Day-to-day cluster inspection |
| `scripts/ray-launch.sh` + `canfar` | Head/workers without new UI |
| Bugfixes that keep existing E2E green | Allowed on this panel |
| New pages, themes, workflows | Belong elsewhere (Dashboard / scripts) |

See [docs/RAY.md](../../docs/RAY.md).
