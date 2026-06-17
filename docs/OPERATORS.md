# Operator guide

Register and publish AstroAI images on the CANFAR Science Platform.

## Images and session types

| Image | Harbor path | Skaha session type | Port | User-facing |
|-------|-------------|-------------------|------|-------------|
| `base` | `images.canfar.net/astroai/base:<tag>` | *(not launched)* | — | Headless parent only |
| `webterm` | `images.canfar.net/astroai/webterm:<tag>` | **Contributed** | 5000 | Browser terminal |
| `vscode` | `images.canfar.net/astroai/vscode:<tag>` | **Contributed** | 5000 | Browser IDE |
| `notebook` | `images.canfar.net/astroai/notebook:<tag>` | **Notebook** | 8888 | JupyterLab |
| `marimo` | `images.canfar.net/astroai/marimo:<tag>` | **Contributed** | 5000 | Reactive notebooks |

Each image carries `io.canfar.skaha.session.type` in its OCI labels (`headless`, `contributed`, or `notebook`) for Harbor inventory.

Build and push:

```bash
make build-all
make push/notebook TAG=26.06
make push/webterm TAG=26.06
```

Do **not** register `base` as a Science Portal session — it is the shared parent layer.

## Contributed sessions (webterm, vscode, marimo)

Register as **Contributed** in the Science Portal.

- `skaha_sessionid` is set in the container environment
- Reverse-proxy path: `/session/contrib/<session-id>/`
- Container listens on port **5000**
- Image entrypoint: `/skaha/startup.sh` → `/cadc/startup-<image>.sh`
- Platform does not override the container command

## Notebook sessions (notebook image only)

Register `images.canfar.net/astroai/notebook:<tag>` as a **Notebook** session type.

- Session ID is passed as the **first argument** to `/skaha/startup.sh`
- `JUPYTER_TOKEN` is also set to the session ID (platform default)
- Reverse-proxy path: `/session/notebook/<session-id>/`
- Container listens on port **8888**
- Jupyter `base_url`: `session/notebook/<session-id>` (matches platform convention)

### Launch template override (required)

The stock Skaha notebook job runs `/skaha-system/start-jupyterlab.sh` from a ConfigMap. That script skips AstroAI session setup (`common-init`, `/scratch` cwd, cache dirs).

**Override the container command** for AstroAI notebook images:

```yaml
containers:
- name: "${skaha.jobname}"
  image: ${software.imageid}
  command: ["/skaha/startup.sh"]
  args:
  - ${skaha.sessionid}
  ports:
  - containerPort: 8888
    protocol: TCP
    name: notebook-port
```

Remove or replace the `start-jupyterlab` ConfigMap volume mount when using this override.

## Image entrypoints

| Image | `/skaha/startup.sh` | `CMD` |
|-------|---------------------|-------|
| `webterm` | → `startup-webterm.sh` | `/cadc/startup-webterm.sh` |
| `vscode` | → `startup-vscode.sh` | `/cadc/startup-vscode.sh` |
| `notebook` | → `startup-notebook.sh "$@"` | `/skaha/startup.sh` |
| `marimo` | → `startup-marimo.sh` | `/cadc/startup-marimo.sh` |

Contributed images work with either `CMD` or `/skaha/startup.sh`. Notebook images expect the session ID as `$1`.

## Science Portal checklist

1. Push session images to `images.canfar.net/astroai/` with a version tag (e.g. `26.06`).
2. Register **Contributed** types for `webterm`, `vscode`, `marimo` — port **5000**.
3. Register **Notebook** type for `notebook` — port **8888**, with launch override above.
4. Do not expose `base` as an interactive session.
5. Document the tag policy for users (monthly `YY.MM`; avoid `latest` in production).

## Local smoke test

Contributed (webterm):

```bash
make build/webterm
./scripts/test-local.sh webterm 5000
```

Notebook:

```bash
make build/notebook
./scripts/test-local.sh notebook 8888
# simulates: /skaha/startup.sh <session-id> on port 8888
```

## Runtime docs for users

Point users to [RUNTIME.md](RUNTIME.md) (also at `/opt/astroai/RUNTIME.md` inside sessions).
