# Contributing

Thanks for helping improve AstroAI session images. Contributions are welcome via GitHub pull requests — docs, scripts, Dockerfiles, and config.

Licensed under [BSD-2-Clause](../LICENSE).

## Documentation map

| Doc | Who it's for |
|-----|----------------|
| [USAGE.md](USAGE.md) | **Session users** — working on CANFAR (`/scratch`, pixi/uv, GPU, AI CLIs) |
| **CONTRIBUTING.md** (this file) | **Developers** — changing this repo |
| [OPERATORS.md](OPERATORS.md) | **AstroAI maintainers** — build, push, register images on CANFAR |
| [README.md](../README.md) | Repo overview, build targets, design principles |

In a running session: `less /opt/astroai/USAGE.md` (after the next image release).

## Get the repo

From an AstroAI session or any machine with Git and [GitHub CLI](https://cli.github.com/):

```bash
gh auth login
gh repo clone astroai/astroai-containers
cd astroai-containers
```

Fork first if you don't have write access:

```bash
gh repo fork astroai/astroai-containers --clone
cd astroai-containers
git checkout -b my-change
```

## Prerequisites for image work

- **Docker** with **buildx** (`docker buildx version`)
- Enough disk for multi-stage builds (~several GB)
- **Harbor push** is maintainer-only — you can build and test locally without registry access

## What to change where

| You want to… | Edit | Rebuild needed |
|--------------|------|----------------|
| User-facing session guide | `docs/USAGE.md` | Yes — copied into `base` as `/opt/astroai/USAGE.md` |
| Contributor / dev workflow | `docs/CONTRIBUTING.md` | No (GitHub only) |
| Portal registration, Harbor | `docs/OPERATORS.md` | No |
| Shell env, caches, `uv`/`pixi` paths | `scripts/astroai-profile.sh` | Yes — `base` and downstream |
| Session startup (`/scratch`, welcome) | `scripts/common-init.sh` | Yes — session image |
| User commands (`astroai-*`) | `scripts/astroai-*`, `scripts/lib/*` | Yes — `base` |
| Session entrypoints | `scripts/startup-*.sh`, `scripts/skaha-startup-*.sh` | Yes — that session image |
| System packages, `gh`, monitoring CLIs | `dockerfiles/base/Dockerfile` | Yes — `base` + downstream |
| Python / uv / pixi foundation | `dockerfiles/python/Dockerfile` | Yes — full stack |
| Jupyter config | `config/jupyter_server_config.py` | Yes — `notebook` |
| CADC client pins | `config/cadc-tools.txt` | Yes — `base` and downstream |
| VS Code UI defaults | `config/openvscode-settings.json` | Yes — `vscode` |
| Bake graph, tags | `docker-bake.hcl`, `Makefile` | Depends on target |

**Lean image rule:** don't add compilers, CUDA, or science stacks to Dockerfiles — those belong in user pixi/uv projects (document in USAGE.md instead).

## Local build and test

```bash
make build/webterm          # one image (+ python → base parents)
make build-all              # full stack

# smoke test as non-root user with fake /arc and /scratch
./scripts/test-local.sh webterm 5000
./scripts/test-local.sh notebook 8888
```

After changing `base` or `scripts/astroai-profile.sh`, verify uv paths:

```bash
./scripts/test-local.sh webterm 5000
# in the container:
source /etc/profile.d/astroai.sh
astroai-status                  # uv python dir should be under $HOME, not /usr/local
uv run python -c "print('ok')"
```

Rebuild the **parent** when you change shared layers — e.g. profile changes need `make build/base` (or `build/webterm` which pulls parents).

## Pull request workflow

```bash
git add -A
git commit -m "Short summary of why"
git push -u origin my-change
gh pr create --fill
```

Keep PRs focused: one logical change (e.g. "fix uv paths" or "document Codex install") is easier to review than mixed doc + Dockerfile refactors.

**Do not commit:** Harbor credentials, `.env` secrets, personal API keys, or large binary artifacts.

## Review checklist (for authors)

- [ ] `docs/USAGE.md` updated if user-visible behavior changed
- [ ] `scripts/astroai-help.sh` updated if commands or paths changed
- [ ] `dockerfiles/base/Dockerfile` `COPY docs/USAGE.md` path matches renamed doc
- [ ] Tested with `./scripts/test-local.sh` when scripts or Dockerfiles changed
- [ ] No unnecessary expansion of the apt layer — prefer pixi/uv in USAGE.md

## Publishing (maintainers)

Image push and Science Portal registration are documented in [OPERATORS.md](OPERATORS.md). Regular contributors do not need Harbor access — open a PR and a maintainer will build, tag, and publish.

## Questions

Open a [GitHub issue](https://github.com/astroai/astroai-containers/issues) or discuss on an existing PR with `gh pr comment`.
