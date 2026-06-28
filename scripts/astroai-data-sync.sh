#!/bin/bash -e
# Copy data between TMP_SCRATCH_DIR (fast SSD) and persistent storage (/arc, etc.).
#
# Called via symlinks:
#   astroai-data-stage <source> [target]   copy persistent → scratch dir
#   astroai-data-sync  <source> <target>   copy scratch dir → persistent

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh
for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

SCRATCH="$(astroai_scratch_dir)"

help_both() {
    cat <<'EOF'
Data transfer between persistent storage (/arc) and TMP_SCRATCH_DIR (/scratch).

  astroai-data-stage <source> [target]   persistent → scratch (fast I/O)
  astroai-data-sync  <source> <target>   scratch → persistent (before session ends)

Run with a command name (not the .sh file) for mode-specific help:
  astroai-data-stage --help
  astroai-data-sync --help
EOF
}

# Determine mode from the command name (image symlinks or *.sh for dev)
CMD="$(basename "$0")"
MODE=""
case "${CMD}" in
    astroai-data-stage|astroai-data-stage.sh) MODE="stage" ;;
    astroai-data-sync|astroai-data-sync.sh)  MODE="sync" ;;
esac

if [[ -z "${MODE}" ]]; then
    case "${1:-}" in
        -h)
            echo "astroai-data-stage / astroai-data-sync — move data between /arc and /scratch." >&2
            echo "Usage: astroai-data-stage <source> [target]" >&2
            echo "       astroai-data-sync <source> <target>" >&2
            echo "  --help for details" >&2
            exit 1
            ;;
        --help) help_both; exit 0 ;;
        *)
            echo "Usage: astroai-data-stage <source> [target]   or   astroai-data-sync <source> <target>" >&2
            exit 1
            ;;
    esac
fi

usage() {
    if [[ "${MODE}" == "stage" ]]; then
        cat <<'EOF' >&2
astroai-data-stage — copy data from persistent storage to scratch.
Usage: astroai-data-stage <source> [target]
  --help for details
EOF
    else
        cat <<'EOF' >&2
astroai-data-sync — copy scratch results to persistent storage.
Usage: astroai-data-sync <source> <target>
  --help for details
EOF
    fi
}

help_full() {
    if [[ "${MODE}" == "stage" ]]; then
        cat <<'EOF'
astroai-data-stage — copy data from persistent storage to scratch.

Usage:
  astroai-data-stage <source> [target]

Options:
  -h          Short help (stderr, exit 1)
  --help      This help (stdout, exit 0)

Copies files or directories from /arc or other persistent storage to
the fast, ephemeral scratch directory (TMP_SCRATCH_DIR, default /scratch)
for high-performance I/O during your session.

Uses rsync under the hood. Asks before overwriting if the target exists.

Examples:
  astroai-data-stage /arc/projects/mygroup/data.fits
  astroai-data-stage /arc/projects/mygroup/survey/ "${TMP_SCRATCH_DIR}/survey/"
EOF
    else
        cat <<'EOF'
astroai-data-sync — copy scratch results to persistent storage.

Usage:
  astroai-data-sync <source> <target>

Options:
  -h          Short help (stderr, exit 1)
  --help      This help (stdout, exit 0)

Syncs files or directories from the ephemeral scratch directory
(TMP_SCRATCH_DIR, default /scratch) back to persistent storage (/arc, etc.).

Uses rsync under the hood. Warns if the source is not under scratch.

Examples:
  astroai-data-sync "${TMP_SCRATCH_DIR}/results/" /arc/projects/mygroup/results/
EOF
    fi
}

case "${1:-}" in
    -h) usage; exit 1 ;;
    --help) help_full; exit 0 ;;
esac

SOURCE="${1:-}"
TARGET="${2:-}"

if [[ -z "${SOURCE}" ]]; then
    usage
    exit 1
fi

if [[ ! -e "${SOURCE}" ]]; then
    echo "Source not found: ${SOURCE}" >&2
    exit 1
fi

require_command() {
    command -v "$1" >/dev/null 2>&1 || { echo "$1 is required but not found." >&2; exit 1; }
}
require_command rsync

astroai_rsync() {
    local src="$1" dst="$2"
    if [[ -d "${src}" ]]; then
        rsync -avh --progress "${src%/}/" "${dst}"
    else
        rsync -avh --progress "${src}" "${dst}"
    fi
}

if [[ "${MODE}" == "stage" ]]; then
    if [[ -z "${TARGET}" ]]; then
        if astroai_scratch_available; then
            TARGET="${SCRATCH}/$(basename "${SOURCE}")"
        else
            echo "${SCRATCH} not writable — specify a target directory." >&2
            exit 1
        fi
    fi

    astroai_info "Stage: ${SOURCE} → ${TARGET}"
    SRC_SIZE="$(du -sh "${SOURCE}" 2>/dev/null | awk '{print $1}' || echo "?")"
    astroai_kv "  size:" "${SRC_SIZE}"

    if [[ -e "${TARGET}" ]]; then
        astroai_warn "  ⚠  Target exists: ${TARGET}"
        read -r -p "  Overwrite? [y/N] " CONFIRM || true
        if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
            astroai_hint "Cancelled."
            exit 0
        fi
    fi

    astroai_info "  copying..."
    astroai_rsync "${SOURCE}" "${TARGET}"
    astroai_ok "✓ staged to ${TARGET}"

elif [[ "${MODE}" == "sync" ]]; then
    if [[ -z "${TARGET}" ]]; then
        usage
        exit 1
    fi

    if [[ "${SOURCE}" != "${SCRATCH}" && "${SOURCE}" != "${SCRATCH}/"* ]]; then
        astroai_warn "⚠  Source is not under ${SCRATCH}: ${SOURCE}"
        astroai_hint "   This command is for syncing scratch data back to persistent storage."
        read -r -p "   Continue? [y/N] " CONFIRM || true
        if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
            astroai_hint "Cancelled."
            exit 0
        fi
    fi

    if astroai_scratch_available; then
        astroai_warn "⚠  Remember: ${SCRATCH} is ephemeral — data there will be wiped when the session ends."
    fi

    astroai_info "Sync: ${SOURCE} → ${TARGET}"
    SRC_SIZE="$(du -sh "${SOURCE}" 2>/dev/null | awk '{print $1}' || echo "?")"
    echo "  size: ${SRC_SIZE}"

    TARGET_DIR="$(dirname "${TARGET}")"
    if [[ -d "${TARGET_DIR}" ]]; then
        echo "  dest free: $(df -h "${TARGET_DIR}" 2>/dev/null | awk 'NR>1{print $4}')"
    fi

    astroai_info "  syncing..."
    astroai_rsync "${SOURCE}" "${TARGET}"
    astroai_ok "✓ synced to ${TARGET}"
fi
