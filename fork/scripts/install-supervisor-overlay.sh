#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install-supervisor-overlay.sh --supervisor /path/to/supervisor [--force]

Installs the amd64-only fork publish workflow into a local Supervisor fork.
Existing differing workflow files are not overwritten unless --force is given.
EOF
}

SUPERVISOR=""
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --supervisor)
      SUPERVISOR="${2:-}"
      shift 2
      ;;
    --force)
      FORCE=true
      shift
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

[[ -n "${SUPERVISOR}" ]] || { usage >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE="${FORK_DIR}/control-plane/supervisor-overlay/.github/workflows/fork-supervisor-build.yml"

[[ -f "${SOURCE}" ]] || { echo "ERROR: Supervisor overlay not found: ${SOURCE}" >&2; exit 1; }
SUPERVISOR="$(cd "${SUPERVISOR}" && pwd)"
[[ -f "${SUPERVISOR}/Dockerfile" && -f "${SUPERVISOR}/supervisor/const.py" ]] || {
  echo "ERROR: ${SUPERVISOR} does not look like a Home Assistant Supervisor repository." >&2
  exit 1
}

TARGET="${SUPERVISOR}/.github/workflows/fork-supervisor-build.yml"
mkdir -p "$(dirname "${TARGET}")"

if [[ -f "${TARGET}" ]]; then
  if cmp -s "${SOURCE}" "${TARGET}"; then
    echo "Supervisor overlay already installed and identical: ${TARGET}"
    exit 0
  fi
  if [[ "${FORCE}" != true ]]; then
    echo "ERROR: ${TARGET} already exists and differs from the managed overlay." >&2
    echo "Review it manually or rerun with --force to replace it." >&2
    exit 1
  fi
fi

cp "${SOURCE}" "${TARGET}"

echo "Installed Supervisor fork workflow: ${TARGET}"
if command -v git >/dev/null; then
  git -C "${SUPERVISOR}" diff --check
fi

echo "Review and commit the workflow in the Supervisor fork before dispatching it."
echo "After the first publish, make the GHCR package public before referencing it from version manifests."
