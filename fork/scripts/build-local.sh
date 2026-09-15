#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  build-local.sh [ova|generic-x86-64|all] /path/to/operating-system

Build outputs:
  ova:
    output_ova/images/haos_ova-*.qcow2.xz
    output_ova/images/haos_ova-*.raucb

  generic-x86-64:
    output_generic_x86_64/images/haos_generic-x86-64-*.img.xz
    output_generic_x86_64/images/haos_generic-x86-64-*.raucb
EOF
}

TARGET="${1:-all}"
REPO="${2:-.}"

case "$TARGET" in
  ova|generic-x86-64|all) ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

REPO="$(cd "$REPO" && pwd)"
cd "$REPO"

command -v docker >/dev/null || { echo "ERROR: docker not found" >&2; exit 1; }
command -v git >/dev/null || { echo "ERROR: git not found" >&2; exit 1; }
docker info >/dev/null 2>&1 || {
  echo "ERROR: Docker daemon is not accessible." >&2
  exit 1
}

if [[ "$(id -u)" -eq 0 ]]; then
  echo "ERROR: Run as a regular user with sudo privileges, matching upstream scripts/enter.sh." >&2
  exit 1
fi

git submodule update --init
bash fork/scripts/policy-check.sh

build_ova() {
  echo "=== Building OVA/QCOW2 for Proxmox ==="
  scripts/enter.sh make O=output_ova ova
}

build_generic() {
  echo "=== Building generic x86-64 direct disk image ==="
  scripts/enter.sh make O=output_generic_x86_64 generic_x86_64
}

case "$TARGET" in
  ova) build_ova ;;
  generic-x86-64) build_generic ;;
  all)
    build_ova
    build_generic
    ;;
esac

echo
echo "Build complete. Run the verification script next:"
echo "  bash fork/scripts/verify-artifacts.sh \"$REPO\""
