# Contributing

Thanks for helping improve AstroAI session images. Contributions are welcome via
GitHub pull requests — docs, scripts, Dockerfiles, and config.

Licensed under [BSD-2-Clause](../LICENSE).

## Documentation map

| Doc | Audience |
|-----|----------|
| [USAGE.md](USAGE.md) | Session users |
| **CONTRIBUTING.md** (this file) | Developers changing this repo |
| [OPERATORS.md](OPERATORS.md) | Maintainers — push / register / smoke |
| [RAY.md](RAY.md) | Ray manager + workers |
| [README.md](../README.md) | Overview and make targets |

In a session: `less /opt/astroai/USAGE.md`.

## Get the repo

```bash
gh auth login
gh repo clone astroai/astroai-containers
cd astroai-containers
```

Fork workflow:

```bash
gh repo fork astroai/astroai-containers --clone
cd astroai-containers
git checkout -b my-change
```

## Prerequisites

- **Docker** with **buildx**
- Disk for multi-stage builds
- Harbor push is maintainer-only — local build/test needs no registry write access

## What to change where

| You want to… | Edit | Rebuild |
|--------------|------|---------|
| User-facing session guide | `docs/USAGE.md` | Yes — copied into `base` as `/opt/astroai/USAGE.md` |
| Contributor / dev workflow | `docs/CONTRIBUTING.md` | No |
| Portal registration, Harbor | `docs/OPERATORS.md` | No |
| Shell env, caches, `uv`/`pixi` paths | `scripts/astroai-profile.sh` | Yes — `base`+ |
| Session startup | `scripts/common-init.sh`, `scripts/startup-*.sh` | Yes |
| System packages | `dockerfiles/base/Dockerfile` | Yes — `base`+ |
| Python / uv / pixi foundation | `dockerfiles/python/Dockerfile` | Full stack |
| Jupyter config | `config/jupyter_server_config.py` | `notebook` |
| Marimo starter notebook | **Edit in** [astroai-lab](https://github.com/astroai/astroai-lab) `data/notebooks/starter.py`, then `make sync-marimo-starter` | `marimo` |
| CADC client list | `config/cadc-tools.txt` | `base`+ |
| **`astroai-lab` CLI** | `config/astroai-lab.in` + `config/astroai-lab.lock` | `base`+ |
| Ray | `config/ray-deps.txt`, `dockerfiles/ray-*`, `ray/`, `scripts/*ray*` | `make build-ray` |
| Bake graph, tags | `docker-bake.hcl`, `Makefile` | Depends |

Keep Dockerfiles lean — compilers, CUDA, and science stacks belong in user
pixi/uv projects (document in USAGE.md).

## Local build and test

```bash
make build/webterm
make build-all
./scripts/test-local.sh webterm 5000
./scripts/test-local.sh notebook 8888
```

After profile or base changes:

```bash
./scripts/test-local.sh webterm 5000
# inside container:
source /etc/profile.d/astroai.sh
astroai-lab doctor
uv run python -c "print('ok')"
```

## Refresh the vendored `astroai-lab` lock

Images install astroai-lab from a pip lockfile, not PyPI:

```bash
cd ../astroai-lab
uv run pytest -q
git tag v0.X.Y  # or bump the git ref in config/astroai-lab.in
cd ../astroai-containers
make lock-astroai-lab
make build-all BUILD_TAG=local
make test-local BUILD_TAG=local
make test-ray BUILD_TAG=local
```

## Writable CADC venv

`/opt/astroai/venv/cadc` is writable so users can run `upgrade-cadc-tools.sh` or
`uv pip install --python /opt/astroai/venv/cadc …` for this session only.
Project deps use pixi/uv under `TMP_SRC_DIR`; caches prefer scratch via
`astroai-lab`.

## Ray tests

```bash
make test-ray BUILD_TAG=local
make test-canfar-ray TAG=26.07
make test-canfar-ray-gpu TAG=26.07
```

| Script | Checks |
|--------|--------|
| `scripts/test-ray-ui-local.sh` | Manager HTML / JSON / redirects |
| `scripts/test-astroai-lab-loop.sh` | Cold start → save → resume in `base` |
| `scripts/test-canfar-ray.sh` | CANFAR manager UI + cluster lifecycle |

Integration tests for the CLI live in
[astroai/astroai-lab](https://github.com/astroai/astroai-lab)
(`tests/integration/test_cold_start_save_resume.py`).

## Marimo starter sync

Canonical `starter.py` lives in **astroai-lab**
(`src/astroai_lab/data/notebooks/starter.py`). The copy under
`config/notebooks/starter.py` is what the marimo image installs — keep them
identical:

```bash
# from astroai-containers (sibling checkout of astroai-lab)
make sync-marimo-starter
```

Startup (`scripts/startup-marimo.sh`) seeds that file once into
`TMP_SRC_DIR/notebooks` and runs `marimo edit starter.py`.

## Marimo AI ↔ astroai-lab upstream integration (done)

`astroai-lab agent setup` now includes a **`marimo`** bundle that writes
`~/.marimo.toml` with OpenRouter config and API key via `_merge_marimo_openrouter`
in `bundles.py`. The startup script calls `astroai-lab agent setup marimo`
at session start (non-destructive; never overwrites user settings).

**What changed:**

- `scripts/startup-marimo.sh`: replaced `agent-env.sh` bridging and manual TOML
  seeding with a single `astroai-lab agent setup marimo` call; opens `starter.py`
  by default.
- `config/marimo.toml`: kept as build-time default template (bundled for reference).

**Verification:** `canfar-verify-agents.sh` checks that `~/.marimo.toml`
contains an OpenRouter section after agent setup.

**Vault / Remote Storage:** keep `canfar_marimo.VOSpaceUI` until upstream `vos`
fsspec lands; then expose a notebook FS variable for marimo Remote Storage.

---

## Pull requests

```bash
git add -A
git commit -m "Short summary of why"
git push -u origin my-change
gh pr create --fill
```

Keep PRs focused. Do not commit Harbor credentials, `.env` secrets, personal API
keys, or large binary artifacts unrelated to the vendored wheel.

### Checklist

- [ ] `docs/USAGE.md` updated when user-visible behavior changes
- [ ] Upstream [astroai-lab](https://github.com/astroai/astroai-lab) updated when CLI or path behavior changes
- [ ] `dockerfiles/base/Dockerfile` still copies `docs/USAGE.md` correctly
- [ ] `./scripts/test-local.sh` run when scripts or Dockerfiles change
- [ ] Image layers stay lean — prefer documenting heavy deps in USAGE.md

## Publishing

Image push and portal registration: [OPERATORS.md](OPERATORS.md).

## Questions

Open a [GitHub issue](https://github.com/astroai/astroai-containers/issues) or
comment on a PR with `gh pr comment`.
