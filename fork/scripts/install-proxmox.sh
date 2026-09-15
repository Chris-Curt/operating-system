#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run this script on a Proxmox VE node as root.

Usage:
  install-proxmox.sh \
    --image /path/haos_ova-VERSION.qcow2.xz \
    --vmid 200 \
    --storage local-lvm \
    [--name haos-fork] [--bridge vmbr0] [--memory 4096] [--cores 2] \
    [--cpu x86-64-v2-AES] [--no-start]

The script refuses to overwrite an existing VMID.
EOF
}

IMAGE=""
VMID=""
STORAGE=""
NAME="haos-fork"
BRIDGE="vmbr0"
MEMORY="4096"
CORES="2"
CPU="x86-64-v2-AES"
START=1

while (($#)); do
  case "$1" in
    --image) IMAGE="${2:?}"; shift ;;
    --vmid) VMID="${2:?}"; shift ;;
    --storage) STORAGE="${2:?}"; shift ;;
    --name) NAME="${2:?}"; shift ;;
    --bridge) BRIDGE="${2:?}"; shift ;;
    --memory) MEMORY="${2:?}"; shift ;;
    --cores) CORES="${2:?}"; shift ;;
    --cpu) CPU="${2:?}"; shift ;;
    --no-start) START=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[[ -n "$IMAGE" && -n "$VMID" && -n "$STORAGE" ]] || {
  usage >&2
  exit 2
}

[[ "$(id -u)" -eq 0 ]] || { echo "ERROR: run as root on the Proxmox node." >&2; exit 1; }
command -v qm >/dev/null || { echo "ERROR: qm not found; run on a Proxmox VE node." >&2; exit 1; }
command -v pvesm >/dev/null || { echo "ERROR: pvesm not found." >&2; exit 1; }
command -v qemu-img >/dev/null || { echo "ERROR: qemu-img not found." >&2; exit 1; }
command -v xz >/dev/null || { echo "ERROR: xz not found." >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 not found." >&2; exit 1; }

[[ -f "$IMAGE" ]] || { echo "ERROR: image not found: $IMAGE" >&2; exit 1; }
[[ "$VMID" =~ ^[0-9]+$ ]] || { echo "ERROR: VMID must be numeric." >&2; exit 1; }
[[ "$MEMORY" =~ ^[0-9]+$ && "$CORES" =~ ^[0-9]+$ ]] || {
  echo "ERROR: memory and cores must be numeric." >&2
  exit 1
}

if qm status "$VMID" >/dev/null 2>&1; then
  echo "ERROR: VMID $VMID already exists; refusing to modify it." >&2
  exit 1
fi

if ! pvesm status | awk 'NR > 1 {print $1}' | grep -Fxq "$STORAGE"; then
  echo "ERROR: Proxmox storage '$STORAGE' not found." >&2
  echo "Available storage IDs:" >&2
  pvesm status >&2
  exit 1
fi

if ! ip link show "$BRIDGE" >/dev/null 2>&1; then
  echo "ERROR: network bridge '$BRIDGE' does not exist." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
created_vm=0
cleanup() {
  rm -rf "$tmpdir"
  if (( created_vm )); then
    echo >&2
    echo "NOTE: VM $VMID was created before the failure." >&2
    echo "Inspect it with: qm config $VMID" >&2
    echo "If you deliberately want to remove it: qm destroy $VMID --purge 1" >&2
  fi
}
trap cleanup EXIT

qcow="$tmpdir/haos.qcow2"
case "$IMAGE" in
  *.qcow2.xz)
    echo "Testing and decompressing QCOW2..."
    xz -t "$IMAGE"
    xz -dc "$IMAGE" > "$qcow"
    ;;
  *.qcow2)
    cp --reflink=auto "$IMAGE" "$qcow"
    ;;
  *)
    echo "ERROR: expected .qcow2 or .qcow2.xz" >&2
    exit 1
    ;;
esac

format="$(qemu-img info --output=json "$qcow" | python3 -c 'import json,sys; print(json.load(sys.stdin)["format"])')"
[[ "$format" == "qcow2" ]] || { echo "ERROR: source is not QCOW2 (format=$format)." >&2; exit 1; }
qemu-img check "$qcow"

echo "Creating VM $VMID..."
qm create "$VMID" \
  --name "$NAME" \
  --memory "$MEMORY" \
  --cores "$CORES" \
  --cpu "$CPU" \
  --machine q35 \
  --bios ovmf \
  --ostype l26 \
  --scsihw virtio-scsi-single \
  --net0 "virtio,bridge=${BRIDGE}" \
  --onboot 1
created_vm=1

# Persist OVMF variables. pre-enrolled-keys=0 keeps Secure Boot disabled.
qm set "$VMID" --efidisk0 "${STORAGE}:0,efitype=4m,pre-enrolled-keys=0"

echo "Importing HAOS disk..."
qm disk import "$VMID" "$qcow" "$STORAGE"

unused="$(
  qm config "$VMID" |
    sed -n 's/^unused0: \([^,]*\).*/\1/p' |
    head -n1
)"
if [[ -z "$unused" ]]; then
  echo "ERROR: imported volume not found as unused0." >&2
  exit 1
fi

qm set "$VMID" --scsi0 "${unused},discard=on,iothread=1"
qm set "$VMID" --boot order=scsi0

echo
qm config "$VMID"

if (( START )); then
  echo
  echo "Starting VM $VMID..."
  qm start "$VMID"
fi

created_vm=0
trap - EXIT
rm -rf "$tmpdir"

echo
echo "Proxmox installation finished."
echo "VMID: $VMID"
echo "Boot disk: scsi0"
echo "Firmware: OVMF/UEFI"
echo "Secure Boot: disabled"
