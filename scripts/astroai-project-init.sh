#!/bin/bash -e
# Create a team workspace under /arc/projects/<name> with standard layout.
#
# Usage:
#   astroai-project-init <name>
#   astroai-project-init <name> --members user1,user2

[[ -f /etc/profile.d/astroai.sh ]] && source /etc/profile.d/astroai.sh
for _libdir in /opt/astroai/lib "$(dirname "${BASH_SOURCE[0]}")/lib" "$(dirname "${BASH_SOURCE[0]}")/../lib"; do
    if [[ -f "${_libdir}/astroai-load.sh" ]]; then
        # shellcheck disable=SC1091
        source "${_libdir}/astroai-load.sh"
        astroai_source_common "${BASH_SOURCE[0]}"
        break
    fi
done

NAME=""
MEMBERS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --members)
            [[ -n "${2:-}" ]] || { echo "--members requires a comma-separated user list" >&2; exit 1; }
            MEMBERS="${2}"
            shift 2
            ;;
        -h|--help)
            sed -n '2,12p' "$0"
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            echo "Usage: astroai-project-init <name> [--members user1,user2]" >&2
            exit 1
            ;;
        *)
            NAME="$1"
            shift
            ;;
    esac
done

if [[ -z "${NAME}" ]]; then
    echo "Usage: astroai-project-init <name> [--members user1,user2]" >&2
    echo "" >&2
    echo "Creates a team workspace under /arc/projects/<name>/ with:" >&2
    echo "  data/        shared datasets" >&2
    echo "  env-saves/   team environment manifests" >&2
    echo "  results/     shared results and outputs" >&2
    exit 1
fi

[[ "${NAME}" =~ ^[a-zA-Z0-9_-]+$ ]] || {
    echo "Invalid project name '${NAME}': use letters, digits, _, - only." >&2
    exit 1
}

if [[ ! -d /arc/projects ]]; then
    echo "/arc/projects is not mounted. Team workspaces require CANFAR's /arc/projects storage." >&2
    exit 1
fi

PROJ_DIR="/arc/projects/${NAME}"

if [[ -d "${PROJ_DIR}" ]]; then
    echo "Project workspace already exists: ${PROJ_DIR}"
else
    echo "Creating ${PROJ_DIR}..."
    mkdir -p "${PROJ_DIR}"/{data,results,env-saves}
    echo ""
fi

astroai_title "Project: ${NAME}"
astroai_kv "  path:" "${PROJ_DIR}"
echo ""

# ── Directory layout ────────────────────────────
echo "Layout:"
for d in "${PROJ_DIR}" "${PROJ_DIR}"/{data,results,env-saves}; do
    if [[ -d "${d}" ]]; then
        echo "  $(basename "${d}")/"
    fi
done
echo ""

# ── ACL guidance ─────────────────────────────────
echo "ACL setup (CANFAR uses POSIX ACLs on /arc):"
echo ""

if command -v getfacl >/dev/null 2>&1; then
    echo "  Current ACLs:"
    getfacl "${PROJ_DIR}" 2>/dev/null | sed 's/^/    /' || true
else
    echo "  (getfacl not available — ACL package is pre-installed in sessions)"
fi

echo ""
echo "  Grant read/write to team members:"
echo "    setfacl -R -m u:username:rwx ${PROJ_DIR}"
echo "    setfacl -R -m d:u:username:rwx ${PROJ_DIR}   # default for new files"
echo ""

if [[ -n "${MEMBERS}" ]]; then
    IFS=',' read -ra MEMBER_LIST <<< "${MEMBERS}"
    for member in "${MEMBER_LIST[@]}"; do
        member="$(echo "${member}" | xargs)"  # trim whitespace
        if [[ -n "${member}" ]]; then
            echo "  Setting ACLs for ${member}..."
            setfacl -R -m "u:${member}:rwx" "${PROJ_DIR}" 2>/dev/null || echo "    (failed — check username: ${member})"
            setfacl -R -m "d:u:${member}:rwx" "${PROJ_DIR}" 2>/dev/null || true
        fi
    done
    echo ""
fi

echo "  View ACLs:  getfacl ${PROJ_DIR}"
echo "  Remove:     setfacl -R -x u:username ${PROJ_DIR}"
echo ""

# ── Quota ────────────────────────────────────────
echo "Quota:"
astroai_quota_line "${PROJ_DIR}" "${NAME}"
echo ""

# ── Next steps ───────────────────────────────────
echo "Next steps:"
echo "  1. Add data:   astroai-data-stage /arc/projects/${NAME}/data/file.fits"
echo "  2. Save envs:  astroai-env-save mylab --to /arc/projects/${NAME}/env-saves/mylab"
echo "  3. List saves: astroai-env-list --team"
echo "  4. Sync results back: astroai-data-sync /scratch/results/ /arc/projects/${NAME}/results/"
