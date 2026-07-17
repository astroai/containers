#!/usr/bin/env bash
# lint-doc-quota.sh — forbid the false "headless consumes session quota"
# claim from re-entering scripts/test-canfar.sh, and require the canonical
# corrective phrasing.
#
# Background: per opencadc/science-platform#1124, session quotas do NOT
# apply to headless kinds on CANFAR/Skaha. A stuck Pending headless session
# is the Skaha scheduling flake, not a concurrent-session quota lock. Early
# versions of scripts/test-canfar.sh had a diagnostic that wrongly told
# operators to "prune stuck sessions so they do not consume the 3-session
# quota" — fixed in commit 2ba4ba9. This guard prevents silent regression.
#
# What this guard checks:
#   1. Negative — forbid `consume the 3-session quota`, the older
#      "small concurrent-session quota" wording, or any permutation of
#      "consume the .* 3-session quota" inside scripts/test-canfar.sh.
#      The exact phrasing is encoded by the regex below; update the regex
#      if you introduce a new variant of the same false claim.
#      Note: the alternation is REQUIRED (no `?` quantifier) so an
#      unqualified "consume the quota" does NOT spuriously match.
#   2. Positive — require the canonical "Headless kinds are quota-exempt"
#      diagnostic in scripts/test-canfar.sh, so a future deletion of the
#      corrective must be replaced by an equivalent (or the test starts
#      failing for the consumer-facing reason it was added).
#
# Scope: deliberately limited to scripts/test-canfar.sh.
#   scripts/test-canfar-session.sh is NOT covered — its orphan-cleanup
#   comments at lines 41 and 106 correctly describe the contributed/notebook
#   session kinds (which DO consume the ~3-session quota). Same for
#   docs/USAGE.md, docs/OPERATORS.md, etc. — only test-canfar.sh runs the
#   headless-pending diagnostic that was the original bug surface.

set -euo pipefail

# Resolve repo root: works whether invoked from Makefile or directly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET="${REPO_ROOT}/scripts/test-canfar.sh"

if [[ ! -r "${TARGET}" ]]; then
    echo "lint-doc-quota: cannot read ${TARGET}" >&2
    exit 1
fi

FAILED=0

# 1. Negative — ban only the three known regression phrasings. The
# alternation is REQUIRED (no `?` quantifier) so that an unqualified
# "consume the quota" (e.g. talking about /arc storage quota) does not
# spuriously match.
if grep -nE 'consume the (small concurrent-session |user'\''s 3-session |3-session )quota' "${TARGET}"; then
    cat >&2 <<EOF

lint-doc-quota: ${TARGET} contains a banned quota-claim phrasing.

The current text from OPERATORS.md: "session quotas do NOT apply to
headless kinds" — so headless sessions consume NO concurrent quota
slot. Replacing the canonical diagnostic with one of the banned
patterns above is the regression we are guarding against.

Fix:
  - Restore the canonical line near the headless-pending diagnostic in
    scripts/test-canfar.sh, e.g.:
      echo "Headless kinds are quota-exempt; this Pending hang is the
            Skaha scheduling flake (opencadc/science-platform#1124), not
            a concurrent-session quota lock." >&2
  - Or rewrite the surrounding diagnostic to mention
    "contributed/notebook consume the (approximately 3) session quota;
    prune to free slots" and "headless is quota-exempt" so the operator
    is steered correctly.

See docs/OPERATORS.md (Platform notes — headless Pending).
EOF
    FAILED=1
fi

# 2. Positive — require the canonical corrective phrasing.
if ! grep -qE 'Headless[^.]*quota-exempt' "${TARGET}"; then
    cat >&2 <<EOF
lint-doc-quota: ${TARGET} is missing the canonical "Headless ... quota-exempt"
diagnostic in the headless-pending branch.

Per opencadc/science-platform#1124, a stuck Pending headless session is the
Skaha scheduling flake, not a quota issue. Express that to operators so
they do not waste time pruning sessions to free quota slots.

Add (or rephrase to match):
    echo "Headless kinds are quota-exempt; this Pending hang is the
          Skaha scheduling flake (opencadc/science-platform#1124), not
          a concurrent-session quota lock." >&2
EOF
    FAILED=1
fi

if (( FAILED == 0 )); then
    echo "lint-doc-quota: ${TARGET} headless-pending diagnostic is canonical."
    exit 0
fi
exit 1
