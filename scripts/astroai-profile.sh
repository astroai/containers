# AstroAI image shell hook — platform PATH only.
# Session paths, caches, and hooks live in canfar-lab (/etc/canfar-lab/profile.sh).
#
# Bash-only (/etc/profile sources profile.d for all login shells, including sh).
if [ -z "${BASH_VERSION:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

[[ -f /etc/canfar-lab/profile.sh ]] && source /etc/canfar-lab/profile.sh

# CADC venv and image scripts — always prepend when missing from PATH.
case ":${PATH}:" in
    *":/opt/astroai/venv/cadc/bin:"*) ;;
    *) export PATH="/opt/astroai/venv/cadc/bin:/opt/astroai/bin:${PATH}" ;;
esac
