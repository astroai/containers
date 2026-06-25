# Minimal JupyterLab config for CANFAR sessions.
import os

c = get_config()  # noqa: F821

c.ServerApp.ip = "0.0.0.0"
c.ServerApp.open_browser = False
c.ServerApp.allow_origin = "*"
c.ServerApp.disable_check_xsrf = True
c.ServerApp.trust_xheaders = True
c.ServerApp.root_dir = "/scratch"
c.ServerApp.log_level = "WARN"
c.FileContentsManager.delete_to_trash = False
c.InlineBackend.figure_formats = {"png", "jpeg", "svg", "pdf"}

# CANFAR proxy handles auth via session token (set in startup-notebook.sh).
c.PasswordIdentityProvider.hashed_password = ""
_token = os.environ.get("JUPYTER_TOKEN", "")
if _token:
    c.IdentityProvider.token = _token

# JupyterLab defaults to /bin/sh when SHELL is unset; astroai.sh requires bash.
c.ServerApp.terminado_settings = {"shell_command": ["/bin/bash", "-l"]}
