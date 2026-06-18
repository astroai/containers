#!/bin/bash -e
# AstroAI user command reference.

cat <<'EOF'
AstroAI commands (on PATH via /opt/astroai/bin)
=================================================

Quick loop
  astroai-status              where am I, gpu, git, disk
  astroai-new [name]          pixi init new project in /scratch

Environment save/resume (/arc-friendly)
  astroai-env-save [name]     save lockfiles to ~/.astroai/saves
  astroai-env-resume <name>   restore on /scratch + pixi install
  astroai-env-list            list saved environments

Home hygiene (shared CephFS)
  astroai-home-usage          disk breakdown under $HOME
  astroai-cache-prune --all-safe   clear pip/uv/pixi caches

Project workflow
  cd /scratch && git clone …  active code on SSD
  pixi install / uv sync      deps into project (not system image)
  git push                    before session ends — scratch is wiped

Dev CLIs (pre-installed)
  gh, rg, fd, bat, fzf, delta, tldr   GitHub + fast search/browse
  gh auth login               one-time GitHub token setup

AI agents (install once to ~/.local/bin on /arc — see RUNTIME.md)
  curl installers: agent, claude, agy, opencode
  npm (needs pixi nodejs): codex, freebuff

Docs: less /opt/astroai/RUNTIME.md  (or see docs/RUNTIME.md in repo)

Storage
  /scratch     active work (ephemeral)
  ~/.cache     tool caches on /arc (prune when large)
  ~/.astroai   env save manifests
EOF
