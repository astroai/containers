#!/bin/bash -e
# Browser terminal: ttyd + tmux on port 5000.

source /cadc/common-init.sh

exec ttyd --writable --port 5000 -w "${PWD}" \
    -t titleFixed="AstroAI Webterm" \
    -t 'theme={"background": "#1e1e2e"}' \
    tmux new-session -A -s astroai bash -l
