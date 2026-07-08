#!/bin/bash -e
# Browser terminal: ttyd + tmux on port 5000 (CANFAR Contributed session type).

export ASTROAI_SESSION_KIND=webterm

source /cadc/common-init.sh

# CANFAR's contributed ingress strips /session/contrib/<id> before forwarding
# (see science-platform helm/skaha-config/ingress-contributed.yaml), so ttyd
# must listen at /. Do not pass --base-path here — unlike vscode/marimo, ttyd
# uses --base-path for incoming request matching, not outbound URL generation.

TTYD_ARGS=(
    --writable
    --port 5000
    --index /cadc/index.html
    -w "${PWD}"
    -t titleFixed="AstroAI Webterm"
    -t 'theme={"background":"#1e1e2e","foreground":"#cdd6f4","cursor":"#f5e0dc","selectionBackground":"#585b70"}'
    -t fontSize=15
    -t fontFamily="Menlo, monospace"
)

exec ttyd "${TTYD_ARGS[@]}" \
    tmux new-session -A -s astroai bash -l
