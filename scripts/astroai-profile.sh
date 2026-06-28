# AstroAI image shell hook — platform PATH + user CLI dirs.
# Session paths, caches, and hooks live in canfar-lab (/etc/canfar-lab/profile.sh).
#
# Bash-only (/etc/profile sources profile.d for all login shells, including sh).
if [ -z "${BASH_VERSION:-}" ]; then
    return 0 2>/dev/null || exit 0
fi

[[ -f /etc/canfar-lab/profile.sh ]] && source /etc/canfar-lab/profile.sh

# CADC venv and image scripts — after user bins, before rest of PATH.
case ":${PATH}:" in
    *":/opt/astroai/venv/cadc/bin:"*) ;;
    *) export PATH="/opt/astroai/venv/cadc/bin:/opt/astroai/bin:${PATH}" ;;
esac

# Team + user CLI installs (CANFAR_LAB_BIN_DIR) ahead of platform paths.
if [[ -n "${CANFAR_LAB_PATH_PREFIX:-}" ]]; then
    IFS=':' read -ra _canfar_lab_path_parts <<< "${CANFAR_LAB_PATH_PREFIX}"
    _canfar_lab_i=""
    for ((_canfar_lab_i=${#_canfar_lab_path_parts[@]}-1; _canfar_lab_i>=0; _canfar_lab_i--)); do
        _canfar_lab_p="${_canfar_lab_path_parts[_canfar_lab_i]}"
        [[ -n "${_canfar_lab_p}" ]] || continue
        case ":${PATH}:" in
            *":${_canfar_lab_p}:"*) ;;
            *) export PATH="${_canfar_lab_p}:${PATH}" ;;
        esac
    done
    unset _canfar_lab_p _canfar_lab_i _canfar_lab_path_parts
fi
