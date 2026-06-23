#!/bin/bash -e
# AstroAI user command reference.

cat <<'EOF'
AstroAI commands (on PATH via /opt/astroai/bin)
=================================================

Quick loop
  astroai-status              where am I, gpu, git, disk, session age
  astroai-new [name]          pixi init + git + GH repo (--uv, --no-git, --no-gh, --astro)
  astroai-clone owner/repo    clone + install deps in one step

Environment save/resume (/arc-friendly)
  astroai-env-save [name]     save lockfiles to ~/.astroai/saves
  astroai-env-resume <name>   restore on /scratch + pixi install
  astroai-env-list            list personal saves
  astroai-env-list --team     list team saves on /arc/projects
  astroai-env-list --all      list personal + team saves

Home hygiene (shared CephFS)
  astroai-home-usage          disk breakdown under $HOME
  astroai-cache-prune --all-safe   clear pip/uv/pixi caches
  astroai-debug               diagnostic report (session, gpu, disk, net)
  astroai-debug --stdout       print only (no file save)

Project workflow
  astroai-clone owner/repo       clone + auto-install on /scratch
  astroai-project-init <name> create team workspace on /arc/projects
  pixi install / uv sync      deps into project (not system image)
  astroai-session-archive     git push + env save + summary (--force, --name)
  git push                    before session ends — scratch is wiped

Dev CLIs (pre-installed)
  gh, rg, fd, bat, fzf, delta, tldr   GitHub + fast search/browse
  gh auth login               one-time GitHub token setup

AI agents (install once to ~/.local/bin on /arc — see USAGE.md)
  astroai-install <tool>     install agent, claude, agy, opencode, codex, freebuff, aider
  curl installers: agent, claude, agy, opencode
  npm (needs pixi nodejs): codex, freebuff

Docs: less /opt/astroai/USAGE.md  (or see docs/USAGE.md in repo)

Storage
  /scratch     active work (ephemeral)
  ~/.cache     tool caches on /arc (prune when large)
  ~/.astroai   env save manifests
  astroai-data-stage <src>  copy data to /scratch for fast I/O
  astroai-data-sync <src> <tgt>  sync /scratch results to persistent
EOF
