#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-.}"
REPO="$(cd "$REPO" && pwd)"

command -v xz >/dev/null || { echo "ERROR: xz not found" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "ERROR: sha256sum not found" >&2; exit 1; }

shopt -s nullglob
qcow=( "$REPO"/output_ova/images/haos_ova-*.qcow2.xz )
img=( "$REPO"/output_generic_x86_64/images/haos_generic-x86-64-*.img.xz )
rauc_ova=( "$REPO"/output_ova/images/haos_ova-*.raucb )
rauc_generic=( "$REPO"/output_generic_x86_64/images/haos_generic-x86-64-*.raucb )

if ((${#qcow[@]} != 1)); then
  echo "ERROR: expected exactly one Proxmox QCOW2 .xz artifact, found ${#qcow[@]}" >&2
  exit 1
fi
if ((${#img[@]} != 1)); then
  echo "ERROR: expected exactly one generic x86-64 .img.xz artifact, found ${#img[@]}" >&2
  exit 1
fi
if ((${#rauc_ova[@]} != 1 || ${#rauc_generic[@]} != 1)); then
  echo "ERROR: expected one RAUC bundle for each supported board." >&2
  exit 1
fi

echo "Testing XZ streams..."
xz -t "${qcow[0]}"
xz -t "${img[0]}"

if command -v qemu-img >/dev/null; then
  tmp="$(mktemp --suffix=.qcow2)"
  trap 'rm -f "$tmp"' EXIT
  echo "Validating QCOW2 structure..."
  xz -dc "${qcow[0]}" > "$tmp"
  qemu-img check "$tmp"
  qemu-img info "$tmp"
  rm -f "$tmp"
  trap - EXIT
else
  echo "NOTE: qemu-img not installed; skipped structural QCOW2 check."
fi

sumfile="$REPO/SHA256SUMS.proxmox-usb"
sha256sum "${qcow[0]}" "${img[0]}" "${rauc_ova[0]}" "${rauc_generic[0]}" > "$sumfile"

echo
echo "Artifacts verified:"
printf '  %s\n' "${qcow[0]}" "${img[0]}" "${rauc_ova[0]}" "${rauc_generic[0]}"
echo "Checksums: $sumfile"
