#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash sync-upstream.sh /path/to/operating-system [upstream-remote-name]

Fetches home-assistant/operating-system dev, rebases your current branch on it,
updates the Buildroot submodule, and runs the fork policy check.

The work tree must be clean.
EOF
}

REPO="${1:-.}"
UPSTREAM="${2:-upstream}"
REPO="$(cd "$REPO" && pwd)"
cd "$REPO"

[[ -z "$(git status --porcelain)" ]] || {
  echo "ERROR: work tree is dirty. Commit or stash first." >&2
  exit 1
}

if ! git remote get-url "$UPSTREAM" >/dev/null 2>&1; then
  git remote add "$UPSTREAM" https://github.com/home-assistant/operating-system.git
fi

git fetch "$UPSTREAM" dev --tags
git rebase "$UPSTREAM/dev"
git submodule update --init
bash fork/scripts/policy-check.sh

echo "Upstream sync completed and fork policy still passes."
