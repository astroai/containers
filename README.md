# AstroAI Containers

Lean CANFAR session images for astronomy and ML development. Published to `images.canfar.net/astroai/`.

Licensed under [BSD-2-Clause](LICENSE).

## Sessions

| Image | Use for | Skaha type |
|-------|---------|------------|
| `webterm` | Browser terminal (ttyd + tmux) | Contributed |
| `vscode` | Browser IDE (OpenVSCode Server) | Contributed |
| `notebook` | JupyterLab | **Notebook** |
| `marimo` | Reactive notebooks | Contributed |
| `base` | Headless parent (not a portal session) | — |

## Documentation

| Doc | Audience |
|-----|----------|
| [docs/USAGE.md](docs/USAGE.md) | **Session users** — quickstart, `gh`, storage, GPU, pixi/uv, AI CLI install |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | **Developers** — clone, build, test, open PRs |
| [docs/OPERATORS.md](docs/OPERATORS.md) | **Platform admins** — Harbor push, Science Portal registration |

In-session: `astroai-help` · `less /opt/astroai/USAGE.md`

## Build

Requires Docker with buildx. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for the full dev loop.

```bash
make build-all          # full stack
make build/vscode       # one image (+ parents)
docker buildx bake      # direct bake
make clean              # remove local images.canfar.net/astroai/*
make clean-all          # clean + prune buildx cache
```

## Local test

```bash
make build/webterm
./scripts/test-local.sh webterm 5000

make build/notebook
./scripts/test-local.sh notebook 8888
```

## Push to Harbor

Maintainers only — see [OPERATORS.md](docs/OPERATORS.md).

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
  USAGE.md      # user-facing session guide
  CONTRIBUTING.md
  OPERATORS.md
scripts/
  startup-*.sh  # session entrypoints
  astroai-*     # env save/resume, help, status, caches
```

## Design

- **Same images for CPU and GPU** — pick the node in the portal; CUDA libs via pixi/uv in the project.
- **Minimal bake stack** — `python` → `base` → four session images; heavy software via pixi or [CVMFS on CANFAR nodes](https://opencadc.github.io/canfar/platform/cvmfs/) ([source](https://github.com/opencadc/canfar/blob/main/docs/platform/cvmfs.md)).
- **Quick feedback loops** — `/scratch` for active work, `astroai-new` / `astroai-env-resume`, caches on `/arc`.
- **Skaha session types** — Contributed (5000) for webterm/vscode/marimo; Notebook (8888) for notebook.

## Contributing

Pull requests welcome — see [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).
