# Headless sessions stuck Pending / AstroAI verify doctor

Maintainer notes from the **26.07** CANFAR validation (2026-07-13) and follow-up A/B
repro (2026-07-13 ~22:57–23:06 UTC, server `canfar` / `ws-uv.canfar.net`).

## Symptoms (incident window earlier the same day)

1. `canfar create headless …` returned a session ID successfully.
2. Session stayed **`Pending`** for **30+ minutes** with:
   - `Start Time`: Unknown
   - `Connect URL`: Unknown
   - Empty `canfar logs`
   - `canfar events` often **HTTP 404** (session not found for events view)
3. Afflicted images included **stock** `images.canfar.net/skaha/base-notebook:latest` and
   `images.canfar.net/astroai/base:26.07`.
4. **Contributed** (`webterm` / `vscode` / `marimo`) and **notebook** kinds reached
   **Running** for the same user/auth/registry config.
5. Stuck Pending sessions consumed the **3 concurrent session** quota.

Impact for AstroAI:

- `make test-canfar` / `scripts/test-canfar.sh` (headless `canfar-verify`) unusable.
- Ray **preflight** + **workers** use `kind=headless` (`ray/manager/canfar_ops.py`) and
  could not join.

## A/B repro (after incident — headless scheduling recovered)

Commands (user authenticated; Harbor registry already in `~/.canfar/config.yaml`):

```bash
# Control — stock notebook
canfar create --name repro-nb --cpu 1 --memory 2 \
  notebook images.canfar.net/skaha/base-notebook:latest

# Stock headless
canfar create --name repro-hl-stock --cpu 1 --memory 1 \
  headless images.canfar.net/skaha/base-notebook:latest -- \
  bash -lc 'echo STOCK_HL_OK; sleep 3'

# AstroAI headless
canfar create --name repro-hl-astroai --cpu 1 --memory 1 \
  headless images.canfar.net/astroai/base:26.07 -- \
  bash /opt/astroai/bin/canfar-verify.sh --quick
```

Observed IDs / outcomes (~6 min poll):

| Kind | Image | ID | Result |
|------|-------|-----|--------|
| notebook | `skaha/base-notebook:latest` | `aze0y0mv` | **Running** (healthy control) |
| headless | `skaha/base-notebook:latest` | `bzu43n12` | **Completed** (~minutes) |
| headless | `astroai/base:26.07` | `gmonuddi` | **Failed** after Running |

Artifacts under `/tmp/headless-repro/` on the maintainer host (create `--debug` logs,
`ps` polls, `info` / `events` / `logs`).

### AstroAI headless failure cause (image/product, not Pending)

`canfar-verify.sh` requires `astroai-lab doctor` to exit 0. On real `/arc/home`,
leftover cache directories under `$HOME` (e.g. `.cache/uv`) made `doctor` exit 1 even
when scratch redirects were correct — **path hygiene**, not missing tools.

Fix (astroai-lab): `doctor` exits 1 only for **`env`**-kind hygiene issues; path
leftovers remain reported (prompt `clean home`) but do not fail verify.

## Questions for CANFAR / science-platform ops

When the Pending hang recurs (or for root-cause of the morning window):

1. Why do some headless sessions never get `Start Time` / pod events while notebook
   and contributed succeed for the same user?
2. Is there a headless-only admission/scheduler queue or imagePullSecrets path that
   can stall without failing the create API?
3. Once headless pods start: confirm session-to-session TCP for Ray ports (6379–6381)
   between contributed manager and headless workers (preflight).

## Maintainer interim gates

Until headless is trusted end-to-end:

```bash
make test-canfar-session IMAGE=webterm TAG=26.07   # contributed/notebook HTTP
CANFAR_TEST_QUICK=1 make test-canfar IMAGE=base TAG=26.07  # headless verify
make test-canfar-ray TAG=26.07                    # needs headless workers
```

Prune stuck Pending sessions before smoke runs (`canfar delete --force <id>`) so they
do not exhaust the session quota.

Ray manager Jobs smoke needs **≥8 GiB** RAM (4 GiB OOMs the dashboard).

## Related docs

- [OPERATORS.md](OPERATORS.md) — publish / register / smoke
- [RAY.md](RAY.md) — manager + headless workers
