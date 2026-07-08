#!/usr/bin/env bash
# Smallest check that peek logic works (no Docker required).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PEEK="${ROOT}/scripts/peek"
chmod +x "${PEEK}"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

printf '# Hello\n\nworld\n' >"${TMP}/note.md"
printf 'plain\n' >"${TMP}/a.txt"
tar -czf "${TMP}/a.tgz" -C "${TMP}" a.txt

"${PEEK}" -h | grep -q Usage
out=$("${PEEK}" -t text "${TMP}/a.txt")
printf '%s\n' "${out}" | grep -q plain
out=$("${PEEK}" -t md "${TMP}/note.md")
printf '%s\n' "${out}" | grep -q Hello
out=$("${PEEK}" "${TMP}/a.tgz")
printf '%s\n' "${out}" | grep -q 'a.txt'
out=$("${PEEK}" "${TMP}/a.tgz" a.txt)
printf '%s\n' "${out}" | grep -q plain

# missing file fails
if "${PEEK}" "${TMP}/missing" 2>/dev/null; then
    echo "peek_selfcheck: expected missing file to fail" >&2
    exit 1
fi

echo "peek_selfcheck: ok"
