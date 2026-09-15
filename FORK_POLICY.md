# Fork policy: Proxmox + x86-64 disk/USB only

This repository is a derivative of `home-assistant/operating-system`.

Supported initial installation artifacts are deliberately limited to:

1. `haos_ova-<version>.qcow2.xz` — QEMU/KVM, specifically the supported Proxmox path.
2. `haos_generic-x86-64-<version>.img.xz` — direct disk image for x86-64 UEFI bare metal, including writing to a USB-attached target disk.

RAUC `.raucb` bundles are retained because they are update artifacts, not additional installation platforms.

The upstream source tree is otherwise kept largely intact to make rebasing and security updates practical. The build matrix is the authoritative list of supported release targets. The OVA post-image hook only emits QCOW2.

Do not add another board or VM disk format without explicitly changing this policy and the policy test.
