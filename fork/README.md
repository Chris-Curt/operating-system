# Proxmox + USB fork workflow

This fork intentionally supports only two HAOS installation targets:

- `ova` -> `haos_ova-<version>.qcow2.xz` for Proxmox/QEMU/KVM.
- `generic-x86-64` -> `haos_generic-x86-64-<version>.img.xz` for direct x86-64 UEFI disk/USB installation.

RAUC `.raucb` files remain enabled because they are update bundles, not extra installation platforms.

## 1. Validate policy

```bash
bash fork/scripts/policy-check.sh
```

## 2. Build locally

Prerequisites are the same as upstream HAOS development: Git, Docker with privileged container support, and enough free disk space.

```bash
bash fork/scripts/build-local.sh all .
```

Build only one target when needed:

```bash
bash fork/scripts/build-local.sh ova .
bash fork/scripts/build-local.sh generic-x86-64 .
```

## 3. Verify artifacts

```bash
bash fork/scripts/verify-artifacts.sh .
```

Expected installation artifacts:

```text
output_ova/images/haos_ova-*.qcow2.xz
output_generic_x86_64/images/haos_generic-x86-64-*.img.xz
```

The verifier also expects the corresponding RAUC bundles and writes `SHA256SUMS.proxmox-usb`.

## 4. Install on Proxmox

Copy the QCOW2-XZ artifact to a Proxmox VE node and run as root:

```bash
bash fork/scripts/install-proxmox.sh \
  --image /path/haos_ova-VERSION.qcow2.xz \
  --vmid 200 \
  --storage local-lvm \
  --bridge vmbr0
```

The script creates a Q35/OVMF VM, disables Secure Boot for the EFI variable disk, imports the QCOW2 disk, attaches it as SCSI and starts the VM unless `--no-start` is supplied. It refuses an existing VMID.

## 5. Install directly to disk/USB

**This erases the complete target disk.** Double-check the device path.

```bash
sudo bash fork/scripts/flash-disk.sh \
  --image output_generic_x86_64/images/haos_generic-x86-64-VERSION.img.xz \
  --target /dev/sdX
```

The script rejects partitions, read-only devices, mounted descendants and active swap descendants, then requires an explicit destructive confirmation.

## 6. CONFIG USB / offline update media

For an already mounted filesystem labelled `CONFIG`:

```bash
bash fork/scripts/make-config-usb.sh \
  --mount /media/CONFIG \
  --raucb /path/haos_generic-x86-64-VERSION.raucb
```

On HAOS import the media with:

```bash
ha os import
```

## 7. Sync with upstream

Keep custom changes on a dedicated branch. With a clean working tree:

```bash
bash fork/scripts/sync-upstream.sh . upstream
```

This fetches `home-assistant/operating-system` `dev`, rebases the current branch, updates the Buildroot submodule and reruns the fork policy check.

## Signing note

Development builds may use the upstream workflow's generated self-signed RAUC certificate. Before distributing persistent production OTA updates, configure a stable RAUC certificate/private key in repository Actions secrets and protect the private key appropriately.
