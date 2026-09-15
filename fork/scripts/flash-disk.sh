#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
DANGEROUS: this erases the complete target disk.

Usage:
  sudo bash flash-disk.sh --image haos_generic-x86-64-VERSION.img.xz --target /dev/sdX [--yes]

Use cases:
  * Write HAOS directly to a USB SSD/stick that will be the final boot medium.
  * Boot a Linux live system from USB and write HAOS to the machine's internal SSD/NVMe.

The script refuses non-disk block devices, read-only disks, mounted descendants,
and active swap descendants.
EOF
}

IMAGE=""
TARGET=""
ASSUME_YES=0

while (($#)); do
  case "$1" in
    --image) IMAGE="${2:?}"; shift ;;
    --target) TARGET="${2:?}"; shift ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[[ -n "$IMAGE" && -n "$TARGET" ]] || { usage >&2; exit 2; }
[[ "$(id -u)" -eq 0 ]] || { echo "ERROR: run with sudo/root." >&2; exit 1; }

for cmd in lsblk blockdev xz dd sync; do
  command -v "$cmd" >/dev/null || { echo "ERROR: missing command: $cmd" >&2; exit 1; }
done

[[ -f "$IMAGE" ]] || { echo "ERROR: image not found: $IMAGE" >&2; exit 1; }
[[ "$IMAGE" == *.img.xz ]] || { echo "ERROR: expected a .img.xz file." >&2; exit 1; }

TARGET="$(readlink -f "$TARGET")"
[[ -b "$TARGET" ]] || { echo "ERROR: target is not a block device: $TARGET" >&2; exit 1; }

type="$(lsblk -dn -o TYPE "$TARGET" | tr -d '[:space:]')"
[[ "$type" == "disk" ]] || {
  echo "ERROR: target must be a whole disk, not a partition/device-mapper node (TYPE=$type)." >&2
  exit 1
}

if [[ "$(blockdev --getro "$TARGET")" != "0" ]]; then
  echo "ERROR: target is read-only." >&2
  exit 1
fi

descendants="$(lsblk -nrpo NAME "$TARGET")"

mounted="$(
  lsblk -nrpo NAME,MOUNTPOINT "$TARGET" |
    awk '$2 != "" {print}'
)"
if [[ -n "$mounted" ]]; then
  echo "ERROR: target or a descendant is mounted; refusing to erase it:" >&2
  echo "$mounted" >&2
  exit 1
fi

if command -v swapon >/dev/null; then
  while read -r swapdev; do
    [[ -z "$swapdev" ]] && continue
    if grep -Fxq "$(readlink -f "$swapdev")" <<<"$descendants"; then
      echo "ERROR: active swap belongs to target disk: $swapdev" >&2
      exit 1
    fi
  done < <(swapon --show=NAME --noheadings 2>/dev/null || true)
fi

echo "Testing compressed image..."
xz -t "$IMAGE"

target_bytes="$(blockdev --getsize64 "$TARGET")"
image_bytes="$(
  xz --robot --list "$IMAGE" 2>/dev/null |
    awk -F '\t' '$1 == "totals" {print $5; exit}'
)"
if [[ "$image_bytes" =~ ^[0-9]+$ ]] && (( target_bytes < image_bytes )); then
  echo "ERROR: target is smaller than the uncompressed image." >&2
  exit 1
fi

echo
echo "SOURCE:"
ls -lh "$IMAGE"
echo
echo "TARGET (WILL BE ERASED):"
lsblk -d -o NAME,PATH,SIZE,MODEL,SERIAL,TRAN "$TARGET"
echo

if (( ! ASSUME_YES )); then
  expected="ERASE $TARGET"
  read -r -p "Type exactly '$expected' to continue: " answer
  [[ "$answer" == "$expected" ]] || {
    echo "Cancelled."
    exit 1
  }
fi

echo "Writing image..."
xz -dc "$IMAGE" | dd of="$TARGET" bs=16M conv=fsync status=progress
sync

if command -v blockdev >/dev/null; then
  blockdev --rereadpt "$TARGET" 2>/dev/null || true
fi
if command -v udevadm >/dev/null; then
  udevadm settle || true
fi

echo
echo "Write completed."
lsblk "$TARGET"
echo
echo "Remove/eject the medium only after all writes have completed."
