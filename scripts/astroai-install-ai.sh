#!/bin/bash -e
# Seed the default AI CLI (Cursor agent) into ~/.local on /arc.
# Skips install if already present — user updates are preserved.

export PATH="${HOME}/.local/bin:/opt/astroai/bin:${PATH}"

if command -v agent >/dev/null 2>&1; then
    exit 0
fi

mkdir -p "${HOME}/.local/bin" "${HOME}/.local/share" "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh" 2>/dev/null || true
export ASTROAI_INSTALL_CACHE="${ASTROAI_INSTALL_CACHE:-/opt/astroai/cache}"

curl -fsS https://cursor.com/install | bash
