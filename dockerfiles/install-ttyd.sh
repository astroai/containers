#!/usr/bin/env bash
# Install pinned ttyd binary with SHA256 verification.
set -euo pipefail

TTYD_VERSION="${1:?ttyd version required}"

ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64) TTYD_BIN=ttyd.x86_64 ;;
    aarch64) TTYD_BIN=ttyd.aarch64 ;;
    *)
        echo "unsupported arch: ${ARCH}" >&2
        exit 1
        ;;
esac

case "${TTYD_VERSION}:${ARCH}" in
    1.7.7:x86_64)
        TTYD_SHA256=8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55
        ;;
    1.7.7:aarch64)
        TTYD_SHA256=b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165
        ;;
    *)
        echo "no SHA256 pin for ttyd ${TTYD_VERSION} on ${ARCH} — update install-ttyd.sh" >&2
        exit 1
        ;;
esac

URL="https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/${TTYD_BIN}"
TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

curl -fsSL -o "${TMP}" "${URL}"
echo "${TTYD_SHA256}  ${TMP}" | sha256sum -c -
install -m 755 "${TMP}" /usr/local/bin/ttyd
trap - EXIT
rm -f "${TMP}"

ttyd --version
