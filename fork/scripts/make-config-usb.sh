#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Prepare an already-mounted USB drive for HAOS offline config/update.

Usage:
  bash make-config-usb.sh --mount /media/CONFIG [--raucb /path/haos_*.raucb] [--authorized-keys ~/.ssh/id_ed25519.pub]

The target filesystem itself must already be FAT32, EXT4, or NTFS and should be
labelled CONFIG. This script does not format disks.
EOF
}

MOUNT=""
RAUCB=""
KEYS=""

while (($#)); do
  case "$1" in
    --mount) MOUNT="${2:?}"; shift ;;
    --raucb) RAUCB="${2:?}"; shift ;;
    --authorized-keys) KEYS="${2:?}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[[ -n "$MOUNT" ]] || { usage >&2; exit 2; }
[[ -d "$MOUNT" ]] || { echo "ERROR: mount directory not found: $MOUNT" >&2; exit 1; }

mkdir -p "$MOUNT/network" "$MOUNT/modules" "$MOUNT/modprobe" "$MOUNT/udev"

if [[ -n "$RAUCB" ]]; then
  [[ -f "$RAUCB" ]] || { echo "ERROR: RAUC bundle not found: $RAUCB" >&2; exit 1; }
  cp -v "$RAUCB" "$MOUNT/"
fi

if [[ -n "$KEYS" ]]; then
  [[ -f "$KEYS" ]] || { echo "ERROR: authorized keys file not found: $KEYS" >&2; exit 1; }
  tr -d '\r' < "$KEYS" > "$MOUNT/authorized_keys"
  chmod 600 "$MOUNT/authorized_keys" 2>/dev/null || true
fi

sync
echo "CONFIG USB content prepared at: $MOUNT"
echo "On HAOS, import later with: ha os import"
