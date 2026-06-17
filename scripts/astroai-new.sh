#!/bin/bash -e
# Start a new pixi project on /scratch for a fast feedback loop.

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh

NAME="${1:-project}"
TARGET="/scratch/${NAME}"

if [[ ! -d /scratch ]]; then
    TARGET="${HOME}/${NAME}"
    echo "No /scratch — creating ${TARGET}" >&2
fi

mkdir -p "${TARGET}"
cd "${TARGET}"

if [[ -f pixi.toml ]]; then
    echo "Already a pixi project: ${TARGET}" >&2
    exit 1
fi

pixi init --no-progress
echo ""
echo "Ready: cd ${TARGET}"
echo "  pixi add python numpy"
echo "  pixi run python -c 'print(42)'"
