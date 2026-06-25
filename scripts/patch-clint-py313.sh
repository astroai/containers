#!/bin/bash
# ponytail: sed patch for unmaintained clint → remove when cadcdata drops/fixes clint
# Fix clint SyntaxWarnings on Python 3.12+ (unmaintained dependency of cadcdata).
set -euo pipefail

VENV="${1:-/opt/astroai/venv/cadc}"

shopt -s nullglob
for colored in "${VENV}"/lib/python*/site-packages/clint/textui/colored.py; do
    sed -i '118s/re\.compile("/re.compile(r"/' "${colored}"
done

for ansi in "${VENV}"/lib/python*/site-packages/clint/packages/colorama/ansitowin32.py; do
    sed -i "43s/re\.compile('/re.compile(r'/" "${ansi}"
done

for prompt in "${VENV}"/lib/python*/site-packages/clint/textui/prompt.py; do
    sed -i "68s/is not ' '/!= ' '/" "${prompt}"
done

if ! "${VENV}/bin/python" -W error::SyntaxWarning -c "import clint" >/dev/null 2>&1; then
    echo "clint patch verification failed" >&2
    exit 1
fi
