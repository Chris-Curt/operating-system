#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  prepare-release-meta.sh dev
  prepare-release-meta.sh stable
  prepare-release-meta.sh rc <number>

Examples:
  bash fork/scripts/prepare-release-meta.sh rc 1
  bash fork/scripts/prepare-release-meta.sh stable
  bash fork/scripts/prepare-release-meta.sh dev
EOF
}

MODE="${1:-}"
RC_NUMBER="${2:-}"
META="buildroot-external/meta"

if [[ ! -f "${META}" ]]; then
  echo "ERROR: ${META} not found. Run this script from the repository root." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${META}"

case "${MODE}" in
  dev)
    if [[ -n "${RC_NUMBER}" ]]; then
      usage >&2
      exit 2
    fi
    NEW_SUFFIX="dev0"
    NEW_DEPLOYMENT="development"
    ;;
  stable)
    if [[ -n "${RC_NUMBER}" ]]; then
      usage >&2
      exit 2
    fi
    NEW_SUFFIX=""
    NEW_DEPLOYMENT="production"
    ;;
  rc)
    if [[ ! "${RC_NUMBER}" =~ ^[0-9]+$ ]]; then
      echo "ERROR: rc requires a numeric release-candidate number." >&2
      usage >&2
      exit 2
    fi
    NEW_SUFFIX="rc${RC_NUMBER}"
    NEW_DEPLOYMENT="staging"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

python3 - "${META}" "${NEW_SUFFIX}" "${NEW_DEPLOYMENT}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
suffix = sys.argv[2]
deployment = sys.argv[3]
text = path.read_text(encoding="utf-8")

text, suffix_count = re.subn(
    r'^VERSION_SUFFIX="[^"]*"$',
    f'VERSION_SUFFIX="{suffix}"',
    text,
    count=1,
    flags=re.MULTILINE,
)
text, deployment_count = re.subn(
    r'^DEPLOYMENT="[^"]*"$',
    f'DEPLOYMENT="{deployment}"',
    text,
    count=1,
    flags=re.MULTILINE,
)

if suffix_count != 1 or deployment_count != 1:
    raise SystemExit("ERROR: Unexpected buildroot-external/meta format; refusing to modify it.")

path.write_text(text, encoding="utf-8")
PY

# shellcheck disable=SC1090
source "${META}"
if [[ -z "${VERSION_SUFFIX}" ]]; then
  VERSION="${VERSION_MAJOR}.${VERSION_MINOR}"
else
  VERSION="${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_SUFFIX}"
fi

echo "Prepared metadata:"
echo "  version:    ${VERSION}"
echo "  deployment: ${DEPLOYMENT}"
echo

case "${MODE}" in
  rc)
    echo "Review and commit buildroot-external/meta before creating the GitHub prerelease."
    echo "Create GitHub tag/release '${VERSION}' and mark it as a prerelease."
    ;;
  stable)
    echo "Review and commit buildroot-external/meta before creating the GitHub release."
    echo "Create GitHub tag/release '${VERSION}' as a normal stable release."
    ;;
  dev)
    echo "Review and commit buildroot-external/meta before resuming normal development."
    echo "The CI workflow will replace dev0 with a unique dev suffix for each development build."
    ;;
esac
