#!/bin/bash -e
# Refresh the default AI CLI (Cursor agent) in ~/.local.

export PATH="${HOME}/.local/bin:/opt/astroai/bin:${PATH}"
export ASTROAI_INSTALL_CACHE="${ASTROAI_INSTALL_CACHE:-/opt/astroai/cache}"

echo "Updating Cursor agent..."
curl -fsS https://cursor.com/install | bash

if command -v agent >/dev/null 2>&1; then
    echo "agent: $(command -v agent)"
    agent --version 2>/dev/null || true
else
    echo "Warning: agent not found on PATH after update." >&2
    exit 1
fi
