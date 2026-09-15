#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

python3 - <<'PY'
import json
from pathlib import Path

path = Path(".github/workflows/matrix.json")
data = json.loads(path.read_text(encoding="utf-8"))
expected = [
    {"id": "ova", "defconfig": "ova", "architecture": "x86-64", "label": "board/ova"},
    {"id": "generic-x86-64", "defconfig": "generic_x86_64", "architecture": "x86-64", "label": "board/generic-x86-64"},
]
if data != expected:
    raise SystemExit(
        "ERROR: build matrix violates fork policy. "
        "Only ova and generic-x86-64 are allowed."
    )
print("OK: build matrix is restricted to ova + generic-x86-64")
PY

OVA_HOOK="buildroot-external/board/pc/ova/haos-hook.sh"
GENERIC_HOOK="buildroot-external/board/pc/generic-x86-64/haos-hook.sh"

test -f "$OVA_HOOK"
test -f "$GENERIC_HOOK"
test -f "buildroot-external/configs/ova_defconfig"
test -f "buildroot-external/configs/generic_x86_64_defconfig"

grep -Fq 'convert_disk_image_virtual qcow2' "$OVA_HOOK"
grep -Fq 'convert_disk_image_xz qcow2' "$OVA_HOOK"

for forbidden in \
    'convert_disk_image_virtual vmdk' \
    'convert_disk_image_virtual vhdx' \
    'convert_disk_image_virtual vdi' \
    'convert_disk_image_zip vmdk' \
    'convert_disk_image_zip vhdx' \
    'convert_disk_image_zip vdi' \
    'convert_disk_image_ova'
do
    if grep -Fq "$forbidden" "$OVA_HOOK"; then
        echo "ERROR: unsupported OVA output is enabled: $forbidden" >&2
        exit 1
    fi
done

grep -Fq 'convert_disk_image_xz' "$GENERIC_HOOK"

grep -Eq '^BOARD_ID=ova$' buildroot-external/board/pc/ova/meta
grep -Eq '^SUPERVISOR_MACHINE=qemux86-64$' buildroot-external/board/pc/ova/meta
grep -Eq '^BOARD_ID=generic-x86-64$' buildroot-external/board/pc/generic-x86-64/meta
grep -Eq '^SUPERVISOR_MACHINE=generic-x86-64$' buildroot-external/board/pc/generic-x86-64/meta

echo "OK: OVA emits QCOW2 only"
echo "OK: generic-x86-64 direct disk image path is present"
echo "OK: board metadata is consistent"
