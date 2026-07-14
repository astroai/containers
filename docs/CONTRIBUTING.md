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
| CADC client list | `config/cadc-tools.txt` | `base`+ |
| **`astroai-lab` CLI** | `vendor/astroai_lab-*.whl` | `base`+ |
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

## Refresh the vendored `astroai-lab` wheel

Images install from `vendor/`, not PyPI:

```bash
cd ../astroai-lab
uv run pytest -q
uv build
cp dist/astroai_lab-0.1.0-py3-none-any.whl ../astroai-containers/vendor/
cd ../astroai-containers
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
