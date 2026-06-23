# Minimal JupyterLab config for CANFAR sessions.
c = get_config()  # noqa: F821

c.ServerApp.ip = "0.0.0.0"
c.ServerApp.open_browser = False
c.ServerApp.allow_origin = "*"
c.ServerApp.disable_check_xsrf = True
c.ServerApp.trust_xheaders = True
c.FileContentsManager.delete_to_trash = False
c.InlineBackend.figure_formats = {"png", "jpeg", "svg", "pdf"}

# CANFAR proxy handles auth; disable local token/password (Jupyter Server 2.x)
c.IdentityProvider.token = ""
c.PasswordIdentityProvider.hashed_password = ""
