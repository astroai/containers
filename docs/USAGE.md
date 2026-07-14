# Session user guide

How to use **AstroAI** session images on the
[CANFAR Science Platform](https://www.opencadc.org/canfar/).

This file ships inside images as `/opt/astroai/USAGE.md`.

| You want… | Read |
|-----------|------|
| This page | First session, storage, tools, troubleshooting |
| `astroai-lab` command detail | [astroai-lab USAGE](https://github.com/astroai/astroai-lab/blob/main/docs/USAGE.md) |
| Ray clusters | [RAY.md](RAY.md) |
| Platform CLI | [opencadc.github.io/canfar](https://opencadc.github.io/canfar/) |

## Names

| Name | Meaning |
|------|---------|
| **AstroAI** | Product images and tools (`images.canfar.net/astroai/*`) |
| **CANFAR** | Platform: [Science Portal](https://www.canfar.net/science-portal), Skaha, `/arc` |
| **`canfar`** | CLI for login and sessions |
| **`astroai-lab`** | Workbench **inside** a running session |

```mermaid
flowchart LR
  Portal[Science Portal] --> Img[AstroAI image]
  Canfar["canfar create"] --> Img
  Img --> Lab["astroai-lab"]
  Lab --> Work["code on /srcdir · data on /scratch · saves on /arc"]
```

---

## Student checklist (notebook-first)

1. Open the [Science Portal](https://www.canfar.net/science-portal).
2. Launch **notebook** (JupyterLab) or **marimo**.
3. Open starter content:
   - Notebook: `/opt/astroai/notebooks/starter.ipynb` or `astroai-lab notebook starter`
   - Marimo: `TMP_SRC_DIR/notebooks/starter.py` (seeded once)
4. Run `astroai-lab kernel ensure` if the kernel is missing (notebook).
5. Run `astroai-lab doctor` — caches should sit under `/scratch`.
6. Persist results to `/arc/projects/…` with `astroai-lab data sync` or `vcp`.

---

## Your first session

### From the portal

1. Log in at [canfar.net/science-portal](https://www.canfar.net/science-portal).
2. Pick an AstroAI image (`webterm`, `vscode`, `notebook`, `marimo`, or `ray-manager`).
3. Choose resources (CPU / memory / GPU node as needed).
4. Open the connect URL when the session is **Running**.

### From the `canfar` CLI

```bash
canfar login
canfar create --name myterm webterm
# or a tagged Harbor image:
canfar create --name myterm contributed images.canfar.net/astroai/webterm:26.07
canfar ps
canfar open <session-id>
```

Inside the session:

```bash
astroai-lab                # status
astroai-lab guide          # cheat sheet
astroai-lab init mylab
astroai-lab push --yes     # before you delete the session
```

```mermaid
flowchart TD
  A[canfar login] --> B[Create session]
  B --> C[Running — open connect URL]
  C --> D[astroai-lab resume or init]
  D --> E[Work]
  E --> F[astroai-lab save / data sync]
  F --> G[astroai-lab push]
  G --> H[canfar delete]
```

---

## How storage works

| Tier | Path | Lifetime | Use |
|------|------|----------|-----|
| Work | `TMP_SRC_DIR` → `/srcdir` | Session | Source, pixi/uv projects |
| Scratch | `TMP_SCRATCH_DIR` → `/scratch` | Session | Data, package caches, temp |
| Home | `/arc/home/<you>` | Persistent | Config, env saves, credentials |
| Projects | `/arc/projects/<group>` | Persistent | Shared datasets and results |

```bash
astroai-lab paths
astroai-lab data stage /arc/projects/mygroup/raw
astroai-lab data sync /scratch/out /arc/projects/mygroup/out
```

Env snapshots: `astroai-lab save` / `resume` → default `~/.astroai/lab/saves/`.

Team layout: `astroai-lab project init <group> --members …`

---

## CADC and VOSpace

Session images include CADC clients on PATH (`/opt/astroai/venv/cadc`):

```bash
cadcget …
vls vos:…
vcp ./file.fits vos:…
canfar login          # platform auth (also used by Ray manager)
```

Upgrade platform CLIs for this session only:

```bash
upgrade-cadc-tools.sh list
upgrade-cadc-tools.sh --upgrade astroai-lab
```

---

## Alliance software (CVMFS)

On CANFAR compute nodes you can load software modules from CVMFS. See the
platform notes:
[CVMFS documentation](https://github.com/opencadc/canfar/blob/main/docs/platform/cvmfs.md).

---

## Package managers

Use **pixi** or **uv** under `TMP_SRC_DIR` for project dependencies. Images stay
lean: compilers, CUDA, and science stacks belong in your project locks, not in
the Docker layer.

```bash
astroai-lab init mylab          # pixi by default
astroai-lab init mylab --uv
```

---

## AI coding tools

```bash
astroai-lab agent setup
astroai-lab agent install kilo    # goose, cline, opencode, …
astroai-lab agent models free
gh auth login
```

Agents and MCP config persist on `/arc` home. Refresh after image upgrades with
`astroai-lab agent update`. Command detail:
[astroai-lab cli.md](https://github.com/astroai/astroai-lab/blob/main/docs/cli.md).

---

## Session notes

| Image | Port / path notes |
|-------|-------------------|
| `webterm` | Contributed `:5000` — ttyd + tmux |
| `vscode` | Contributed `:5000` — OpenVSCode; base-path set for `/session/contrib/<id>/` |
| `marimo` | Contributed `:5000` — listens at `/` (ingress strips the contrib prefix) |
| `notebook` | Notebook `:8888` — Jupyter `base_url` is `session/notebook/<id>` |
| `ray-manager` | See [RAY.md](RAY.md) — Dashboard at `connectURL/dashboard/` |

CPU and GPU use the **same** image; request a GPU node in the portal when needed.

---

## Environment variables

| Variable | Set by | Meaning |
|----------|--------|---------|
| `TMP_SRC_DIR` | Skaha | Work directory (default `/srcdir`) |
| `TMP_SCRATCH_DIR` | Skaha | Scratch (default `/scratch`) |
| `skaha_sessionid` | Skaha | Session id (proxy paths) |
| `ASTROAI_LAB_*` | Optional | Workbench overrides — [config.md](https://github.com/astroai/astroai-lab/blob/main/docs/config.md) |
| `ASTROAI_RAY_JOBS_ADDRESS` | ray-manager startup | Local Jobs API (`http://127.0.0.1:8265`) |

Login shells load AstroAI profile helpers so caches prefer scratch.

---

## Diagnostics

```bash
astroai-lab doctor --json
astroai-lab status --json
astroai-lab check --strict
astroai-lab tools
```

---

## Troubleshooting

| Symptom | Action |
|---------|--------|
| Lost files after session end | They were on `/srcdir` or `/scratch` — sync to `/arc` next time before exit |
| Home quota full | `astroai-lab status`; `astroai-lab clean home --all-safe --dry-run` |
| Caches under `$HOME` | Use a login shell; `astroai-lab doctor` |
| Session stuck **Pending** | Check `canfar ps` / `canfar events`; prune stuck sessions (`canfar prune` / delete) — quota is small |
| Marimo / UI 404 | Confirm connect URL trailing path; contrib ingress strips `/session/contrib/<id>` |
| Need Ray | Follow [RAY.md](RAY.md); manager memory **≥8 GiB** for Jobs/Dashboard |

---

## Related

- [astroai-lab](https://github.com/astroai/astroai-lab) — detailed CLI
- [astroai-workload](https://github.com/astroai/astroai-workload) — Ray Jobs from Python
- [OPERATORS.md](OPERATORS.md) — maintainers
- [CONTRIBUTING.md](CONTRIBUTING.md) — image development
