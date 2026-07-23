# CI path shim

The Actions workflow uses `working-directory: astroai-containers/...`.
These symlinks map that prefix onto the real repo layout so the Docker-free
gate can run after a normal `actions/checkout` (repo root).
