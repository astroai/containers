# AstroAI Containers

Lean CANFAR session images for astronomy and ML development. Published to `images.canfar.net/astroai/`.

## Sessions

| Image | Use for | Skaha type |
|-------|---------|------------|
| `webterm` | Browser terminal (ttyd + tmux) | Contributed |
| `vscode` | Browser IDE (OpenVSCode Server) | Contributed |
| `notebook` | JupyterLab | **Notebook** |
| `marimo` | Reactive notebooks | Contributed |
| `base` | Headless parent (not a portal session) | — |

**User guide:** [docs/RUNTIME.md](docs/RUNTIME.md) — quickstart, storage, GPU, pixi/uv, command reference.

**Operator guide:** [docs/OPERATORS.md](docs/OPERATORS.md) — Harbor push, Science Portal registration.

In-session: `astroai-help` · `less /opt/astroai/RUNTIME.md`

## Build

Requires Docker with buildx.

```bash
make build-all          # full stack
make build/vscode       # one image (+ parents)
docker buildx bake      # direct bake
```

## Local test

```bash
make build/webterm
./scripts/test-local.sh webterm 5000

make build/notebook
./scripts/test-local.sh notebook 8888
```

## Push to Harbor

```bash
make build/vscode
make push/vscode TAG=26.06
```

## Layout

```
dockerfiles/
  python/       # 3.13-slim + uv + pixi
  base/         # headless: git, monitoring, CLI, astroai-* wrappers
  webterm/      # contributed: ttyd + tmux
  vscode/       # contributed: OpenVSCode Server
  notebook/     # notebook: JupyterLab + ipykernel (port 8888)
  marimo/       # contributed: marimo
docs/
  RUNTIME.md    # user-facing session guide
  OPERATORS.md  # portal registration
scripts/
  startup-*.sh  # session entrypoints
  astroai-*     # env save/resume, help, status, caches
```

## Design

- **Same images for CPU and GPU** — pick the node in the portal; CUDA libs via pixi/uv in the project.
- **Minimal bake stack** — `python` → `base` → four session images.
- **Quick feedback loops** — `/scratch` for active work, `astroai-new` / `astroai-env-resume`, caches on `/arc`.
- **Skaha session types** — Contributed (5000) for webterm/vscode/marimo; Notebook (8888) for notebook.
