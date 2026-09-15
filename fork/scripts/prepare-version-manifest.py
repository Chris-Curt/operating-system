#!/usr/bin/env python3
"""Prepare a Home Assistant version manifest for the two-target fork."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

CHANNELS = ("stable", "beta", "dev")
SUPPORTED_MACHINES = ("default", "qemux86-64", "generic-x86-64")
SUPPORTED_BOARDS = ("ova", "generic-x86-64")
REQUIRED_TOP_LEVEL = (
    "channel",
    "supervisor",
    "homeassistant",
    "hassos",
    "ota",
    "cli",
    "dns",
    "audio",
    "multicast",
    "observer",
    "images",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Update one stable/beta/dev JSON file in a fork of home-assistant/version "
            "for the Proxmox + generic-x86-64 HAOS fork."
        )
    )
    parser.add_argument("--version-repo", required=True, type=Path)
    parser.add_argument("--channel", required=True, choices=CHANNELS)
    parser.add_argument("--os-version", required=True)
    parser.add_argument("--supervisor-version", required=True)
    parser.add_argument("--github-owner", required=True)
    parser.add_argument("--os-repo", default="operating-system")
    parser.add_argument(
        "--core-version",
        help=(
            "Optional custom Core version. If omitted, existing Core versions from "
            "the source manifest are preserved."
        ),
    )
    parser.add_argument(
        "--core-image-template",
        help=(
            "Optional Core image template, e.g. ghcr.io/owner/{machine}-homeassistant. "
            "Use only after those images have actually been published."
        ),
    )
    return parser.parse_args()


def validate_version(value: str, label: str) -> None:
    if not re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z._+-]*", value):
        raise SystemExit(f"ERROR: Invalid {label}: {value!r}")


def main() -> None:
    args = parse_args()
    validate_version(args.os_version, "OS version")
    validate_version(args.supervisor_version, "Supervisor version")
    if args.core_version:
        validate_version(args.core_version, "Core version")
    if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,38}[A-Za-z0-9])?", args.github_owner):
        raise SystemExit(f"ERROR: Invalid GitHub owner: {args.github_owner!r}")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.os_repo):
        raise SystemExit(f"ERROR: Invalid OS repository name: {args.os_repo!r}")

    repo = args.version_repo.expanduser().resolve()
    manifest_path = repo / f"{args.channel}.json"
    if not manifest_path.is_file():
        raise SystemExit(f"ERROR: Manifest not found: {manifest_path}")

    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as err:
        raise SystemExit(f"ERROR: Cannot parse {manifest_path}: {err}") from err

    missing = [key for key in REQUIRED_TOP_LEVEL if key not in data]
    if missing:
        raise SystemExit(f"ERROR: Manifest is missing required keys: {', '.join(missing)}")
    if data["channel"] != args.channel:
        raise SystemExit(
            f"ERROR: {manifest_path.name} declares channel {data['channel']!r}, "
            f"expected {args.channel!r}."
        )
    if not isinstance(data["homeassistant"], dict) or not isinstance(data["images"], dict):
        raise SystemExit("ERROR: Unexpected manifest structure for homeassistant/images.")

    missing_machines = [
        machine for machine in SUPPORTED_MACHINES if machine not in data["homeassistant"]
    ]
    if missing_machines:
        raise SystemExit(
            "ERROR: Source manifest lacks required Home Assistant machine keys: "
            + ", ".join(missing_machines)
        )

    data["supervisor"] = args.supervisor_version
    data["hassos"] = {board: args.os_version for board in SUPPORTED_BOARDS}
    data["homeassistant"] = {
        machine: data["homeassistant"][machine] for machine in SUPPORTED_MACHINES
    }

    owner_registry = args.github_owner.lower()
    data["images"]["supervisor"] = (
        f"ghcr.io/{owner_registry}/{{arch}}-hassio-supervisor"
    )
    data["ota"] = (
        f"https://github.com/{args.github_owner}/{args.os_repo}/releases/download/"
        "{version}/{os_name}_{board}-{version}.raucb"
    )

    if bool(args.core_version) != bool(args.core_image_template):
        raise SystemExit(
            "ERROR: --core-version and --core-image-template must be supplied together."
        )
    if args.core_version and args.core_image_template:
        if "{machine}" not in args.core_image_template:
            raise SystemExit("ERROR: --core-image-template must contain {machine}.")
        data["homeassistant"] = {
            machine: args.core_version for machine in SUPPORTED_MACHINES
        }
        data["images"]["core"] = args.core_image_template

    manifest_path.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(f"Updated {manifest_path}")
    print(f"  channel:    {args.channel}")
    print(f"  HAOS:       {args.os_version} ({', '.join(SUPPORTED_BOARDS)})")
    print(f"  Supervisor: {args.supervisor_version}")
    print(f"  OTA:        {data['ota']}")
    print(f"  Supervisor image: {data['images']['supervisor']}")
    if args.core_version:
        print(f"  Core:       {args.core_version}")
        print(f"  Core image: {data['images']['core']}")
    else:
        print("  Core:       preserved from source manifest")


if __name__ == "__main__":
    main()
