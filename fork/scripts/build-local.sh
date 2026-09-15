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

The upstream scripts/enter.sh always mounts the repository path `output` as
/build/output. This helper safely points that path at a target-specific host
output directory for each build.
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

DEFAULT_OUTPUT="${REPO}/output"
OUTPUT_LINK_ACTIVE=false

cleanup_output_link() {
  if [[ "$OUTPUT_LINK_ACTIVE" == true && -L "$DEFAULT_OUTPUT" ]]; then
    rm -f "$DEFAULT_OUTPUT"
  fi
  OUTPUT_LINK_ACTIVE=false
}
trap cleanup_output_link EXIT

prepare_output_link() {
  local target_dir="$1"
  local resolved=""

  if [[ -L "$DEFAULT_OUTPUT" ]]; then
    resolved="$(readlink -f "$DEFAULT_OUTPUT" || true)"
    case "$resolved" in
      "${REPO}/output_ova"|"${REPO}/output_generic_x86_64")
        echo "Removing stale managed output link: ${DEFAULT_OUTPUT} -> ${resolved}"
        rm -f "$DEFAULT_OUTPUT"
        ;;
      *)
        echo "ERROR: Refusing to replace unmanaged symlink ${DEFAULT_OUTPUT} -> ${resolved:-unknown}." >&2
        exit 1
        ;;
    esac
  elif [[ -e "$DEFAULT_OUTPUT" ]]; then
    echo "ERROR: ${DEFAULT_OUTPUT} already exists as a real file/directory." >&2
    echo "Move or remove it before using this target-separated build helper." >&2
    exit 1
  fi

  mkdir -p "$target_dir"
  ln -s "$target_dir" "$DEFAULT_OUTPUT"
  OUTPUT_LINK_ACTIVE=true
}

finish_output_link() {
  cleanup_output_link
}

build_target() {
  local label="$1"
  local make_target="$2"
  local target_dir="$3"

  echo "=== Building ${label} ==="
  prepare_output_link "$target_dir"
  scripts/enter.sh make "$make_target"
  finish_output_link
}

build_ova() {
  build_target "OVA/QCOW2 for Proxmox" "ova" "${REPO}/output_ova"
}

build_generic() {
  build_target "generic x86-64 direct disk image" "generic_x86_64" "${REPO}/output_generic_x86_64"
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
