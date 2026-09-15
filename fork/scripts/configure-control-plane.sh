#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  configure-control-plane.sh \
    --manifest-base https://raw.githubusercontent.com/OWNER/version/master \
    --haos /path/to/operating-system \
    --supervisor /path/to/supervisor

The script updates exactly these source locations:
  operating-system/buildroot-external/package/hassio/hassio.mk
    HASSIO_VERSION_URL

  supervisor/supervisor/const.py
    URL_HASSIO_APPARMOR
    URL_HASSIO_VERSION

It refuses unexpected or duplicate assignments instead of silently patching an
unknown upstream layout.
EOF
}

MANIFEST_BASE=""
HAOS=""
SUPERVISOR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest-base)
      MANIFEST_BASE="${2:-}"
      shift 2
      ;;
    --haos)
      HAOS="${2:-}"
      shift 2
      ;;
    --supervisor)
      SUPERVISOR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "${MANIFEST_BASE}" && -n "${HAOS}" && -n "${SUPERVISOR}" ]] || {
  usage >&2
  exit 2
}

case "${MANIFEST_BASE}" in
  https://*) ;;
  *)
    echo "ERROR: --manifest-base must be an https:// URL." >&2
    exit 1
    ;;
esac

[[ "${MANIFEST_BASE}" != *' '* && "${MANIFEST_BASE}" != *$'\n'* ]] || {
  echo "ERROR: --manifest-base contains whitespace." >&2
  exit 1
}
MANIFEST_BASE="${MANIFEST_BASE%/}"

HAOS="$(cd "${HAOS}" && pwd)"
SUPERVISOR="$(cd "${SUPERVISOR}" && pwd)"

HAOS_FILE="${HAOS}/buildroot-external/package/hassio/hassio.mk"
SUPERVISOR_FILE="${SUPERVISOR}/supervisor/const.py"

[[ -f "${HAOS_FILE}" ]] || { echo "ERROR: ${HAOS_FILE} not found." >&2; exit 1; }
[[ -f "${SUPERVISOR_FILE}" ]] || { echo "ERROR: ${SUPERVISOR_FILE} not found." >&2; exit 1; }

python3 - "${HAOS_FILE}" "${SUPERVISOR_FILE}" "${MANIFEST_BASE}" <<'PY'
from __future__ import annotations

from pathlib import Path
import re
import sys

haos_path = Path(sys.argv[1])
supervisor_path = Path(sys.argv[2])
base = sys.argv[3]


def replace_exact_assignment(
    path: Path,
    pattern: str,
    replacement: str,
    label: str,
) -> None:
    text = path.read_text(encoding="utf-8")
    new_text, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(
            f"ERROR: Expected exactly one {label} assignment in {path}; found {count}. "
            "Upstream layout may have changed."
        )
    path.write_text(new_text, encoding="utf-8")


replace_exact_assignment(
    haos_path,
    r'^HASSIO_VERSION_URL\s*=\s*"https://[^"\n]+/"$',
    f'HASSIO_VERSION_URL = "{base}/"',
    "HASSIO_VERSION_URL",
)
replace_exact_assignment(
    supervisor_path,
    r'^URL_HASSIO_APPARMOR\s*=\s*"https://[^"\n]+/apparmor_\{channel\}\.txt"$',
    f'URL_HASSIO_APPARMOR = "{base}/apparmor_{{channel}}.txt"',
    "URL_HASSIO_APPARMOR",
)
replace_exact_assignment(
    supervisor_path,
    r'^URL_HASSIO_VERSION\s*=\s*"https://[^"\n]+/\{channel\}\.json"$',
    f'URL_HASSIO_VERSION = "{base}/{{channel}}.json"',
    "URL_HASSIO_VERSION",
)
PY

echo "Configured manifest base: ${MANIFEST_BASE}"
echo
grep '^HASSIO_VERSION_URL' "${HAOS_FILE}"
grep '^URL_HASSIO_APPARMOR' "${SUPERVISOR_FILE}"
grep '^URL_HASSIO_VERSION' "${SUPERVISOR_FILE}"

echo
if command -v git >/dev/null; then
  git -C "${HAOS}" diff --check
  git -C "${SUPERVISOR}" diff --check
fi

echo "Review and commit the changes in both repositories together."
