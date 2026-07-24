#!/bin/sh
#
# Regression test for `make -s lock-check`. Proves that injecting even a
# single trailing junk line into either committed lockfile surfaces as a
# non-zero exit on the gate. Self-restoring on any exit path (success,
# failure, or signal) via an EXIT trap, so the working tree ends up clean
# even if the runner is killed mid-script.
#
# This test exists because `make -s lock-check` is the load-bearing
# reproducibility gate for the no-`==` / no-`<=` model this project is
# built on. If a future refactor weakens it (e.g., adds `|| true` or
# `cmp -s ... || echo "ignore"`), this script fails loudly instead of
# silently letting drift past CI.
set -e

# Resolve repo root so this script works whether invoked directly or
# through a make target / ci.yml working-directory.
SCRIPT_DIR=$(CDPATH="" cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH="" cd -- "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

RAY_LOCK="config/ray-deps.lock"
LAB_LOCK="config/astroai-lab.lock"

# Sanity check: both lockfiles must exist on disk at the time the
# script runs. If a future refactor moves them, fail loud rather than
# silently passing on a no-op.
if [ ! -f "$RAY_LOCK" ] || [ ! -f "$LAB_LOCK" ]; then
    echo "ERROR: expected $RAY_LOCK and $LAB_LOCK to exist in $REPO_ROOT" >&2
    exit 2
fi

# Defensive cleanup: a previous SIGKILL'd run (no trap fires) can leave
# .bak files behind on disk; this script reads them on the next run if
# `cp` were silent. Force-remove, then re-create.
rm -f "${RAY_LOCK}.bak" "${LAB_LOCK}.bak"

# Atomic backup of both lockfiles. Each `.bak` is a sibling file
# restored by the EXIT trap on any exit path.
cp "$RAY_LOCK" "${RAY_LOCK}.bak"
cp "$LAB_LOCK" "${LAB_LOCK}.bak"

restore() {
    # Idempotent + SIGKILL-safe: mv -f succeeds even if the destination
    # already exists, and `|| true` keeps `set -e` from tripping on the
    # rare case where the bak itself was lost. The trailing rm -f cleans
    # up bak residue so a subsequent run starts from a known state.
    mv -f "${RAY_LOCK}.bak" "$RAY_LOCK" 2>/dev/null || true
    mv -f "${LAB_LOCK}.bak" "$LAB_LOCK" 2>/dev/null || true
    rm -f "${RAY_LOCK}.bak" "${LAB_LOCK}.bak"
}
trap restore EXIT INT TERM

# Probe 1: drift ray-deps.lock. `make -s lock-check` calls `uv pip
# compile` to /tmp/ then `cmp` against the committed file; `cmp -s`
# is byte-strict, so any appended junk (even a # comment) must trip
# the gate.
echo "== Probing ray-deps.lock drift detection =="
printf '\n# deliberate-drift probe\n' >> "$RAY_LOCK"
if make -s lock-check >/dev/null 2>&1; then
    echo "ERROR: make -s lock-check passed on drifted ray-deps.lock" >&2
    echo "The hard-fail gate is wedged open. Refactor regression." >&2
    exit 1
fi
echo "OK: gate tripped on ray-deps.lock drift"

# Explicit mid-script restore of ray-deps.lock. This is duplicated
# below by the trap, but the duplication is intentional: the trap also
# restores astroai-lab.lock, which we deliberately leave drifted for
# probe 2. Without this explicit `cp`, probe 2 would inherit probe 1's
# drift (and we'd test the wrong thing).
cp "${RAY_LOCK}.bak" "$RAY_LOCK"

# Probe 2: drift astroai-lab.lock only.
echo "== Probing astroai-lab.lock drift detection =="
printf '\n# deliberate-drift probe\n' >> "$LAB_LOCK"
if make -s lock-check >/dev/null 2>&1; then
    echo "ERROR: make -s lock-check passed on drifted astroai-lab.lock" >&2
    echo "The hard-fail gate is wedged open. Refactor regression." >&2
    exit 1
fi
echo "OK: gate tripped on astroai-lab.lock drift"

# Explicit restore of astroai-lab.lock BEFORE the final sanity check.
# Without this, the sanity check below would still see astroai-lab.lock
# drifted (the trap only fires on script exit, AFTER this block).
cp "${LAB_LOCK}.bak" "$LAB_LOCK"

# Sanity sweep on the restored (clean) tree: gate must pass cleanly.
echo "== Sanity check on restored (clean) lockfiles =="
if ! make -s lock-check >/tmp/lock-check-sanity.out 2>&1; then
    echo "ERROR: make -s lock-check failed even after explicit restore" >&2
    echo "Restoration or the clean baseline regressed." >&2
    echo "----- make -s lock-check output -----" >&2
    cat /tmp/lock-check-sanity.out >&2 || true
    echo "----- end -----" >&2
    exit 1
fi
echo "OK: gate passes on clean baseline"

# The EXIT trap will then re-restore both lockfiles from .bak on
# script exit (no-op restoration, but keeps the working tree invariant
# clean). This graveyard section is an audit trail only; the trap
# runs cleanup automatically.
echo ""
echo "SUCCESS: both gates trip on drift and pass on clean baseline."
