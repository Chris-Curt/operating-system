#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  setup-control-plane-forks.sh [--workspace DIR] [--with-core]

Creates or reuses personal forks of:
  home-assistant/supervisor  (required for independent update source)
  home-assistant/version     (required for independent manifests)

Optional:
  home-assistant/core        (required when Home Assistant Core itself is modified)

Existing repositories are accepted only when GitHub reports them as forks of the
exact expected upstream repository.
EOF
}

WORKSPACE="${HOME}/src/ha-fork"
WITH_CORE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)
      WORKSPACE="${2:-}"
      [[ -n "${WORKSPACE}" ]] || { echo "ERROR: --workspace requires a directory." >&2; exit 2; }
      shift 2
      ;;
    --with-core)
      WITH_CORE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v gh >/dev/null || { echo "ERROR: GitHub CLI (gh) not found." >&2; exit 1; }
command -v git >/dev/null || { echo "ERROR: git not found." >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq not found." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not authenticated." >&2; exit 1; }

OWNER="$(gh api user --jq '.login')"
[[ -n "${OWNER}" ]] || { echo "ERROR: Could not determine authenticated GitHub user." >&2; exit 1; }

mkdir -p "${WORKSPACE}"
WORKSPACE="$(cd "${WORKSPACE}" && pwd)"

repos=(
  "home-assistant/supervisor|main"
  "home-assistant/version|master"
)
if [[ "${WITH_CORE}" == true ]]; then
  repos+=("home-assistant/core|dev")
fi

ensure_fork() {
  local upstream="$1"
  local default_branch="$2"
  local name="${upstream##*/}"
  local fork="${OWNER}/${name}"
  local local_dir="${WORKSPACE}/${name}"
  local fork_json=""
  local is_fork
  local parent

  echo "=== ${upstream} ==="

  if fork_json="$(gh api "repos/${fork}" 2>/dev/null)"; then
    is_fork="$(jq -r '.fork' <<<"${fork_json}")"
    parent="$(jq -r '.parent.full_name // ""' <<<"${fork_json}")"
    if [[ "${is_fork}" != "true" || "${parent}" != "${upstream}" ]]; then
      echo "ERROR: ${fork} already exists but is not a fork of ${upstream}." >&2
      exit 1
    fi
    echo "Using existing fork ${fork}."
  else
    echo "Creating fork ${fork} from ${upstream}."
    gh repo fork "${upstream}" --clone=false

    # GitHub fork creation can be briefly asynchronous. Query a few times and
    # fail rather than cloning an unresolved or unrelated repository.
    fork_json=""
    for _ in 1 2 3 4 5 6; do
      if fork_json="$(gh api "repos/${fork}" 2>/dev/null)"; then
        break
      fi
      fork_json=""
      sleep 2
    done
    [[ -n "${fork_json}" ]] || { echo "ERROR: Fork ${fork} did not become available." >&2; exit 1; }

    is_fork="$(jq -r '.fork' <<<"${fork_json}")"
    parent="$(jq -r '.parent.full_name // ""' <<<"${fork_json}")"
    if [[ "${is_fork}" != "true" || "${parent}" != "${upstream}" ]]; then
      echo "ERROR: Created repository ${fork} does not report expected parent ${upstream}." >&2
      exit 1
    fi
  fi

  if [[ -e "${local_dir}" ]]; then
    [[ -d "${local_dir}/.git" ]] || { echo "ERROR: ${local_dir} exists but is not a Git repository." >&2; exit 1; }
    local origin
    origin="$(git -C "${local_dir}" remote get-url origin 2>/dev/null || true)"
    case "${origin}" in
      "https://github.com/${fork}.git"|"git@github.com:${fork}.git"|"https://github.com/${fork}") ;;
      *)
        echo "ERROR: ${local_dir} origin is '${origin:-unset}', expected ${fork}." >&2
        exit 1
        ;;
    esac
  else
    gh repo clone "${fork}" "${local_dir}"
  fi

  if git -C "${local_dir}" remote get-url upstream >/dev/null 2>&1; then
    git -C "${local_dir}" remote set-url upstream "https://github.com/${upstream}.git"
  else
    git -C "${local_dir}" remote add upstream "https://github.com/${upstream}.git"
  fi

  git -C "${local_dir}" fetch --prune upstream "${default_branch}"
  echo "Fork ready: ${fork} -> ${local_dir}"
}

for spec in "${repos[@]}"; do
  IFS='|' read -r upstream default_branch <<<"${spec}"
  ensure_fork "${upstream}" "${default_branch}"
done

echo
echo "Control-plane forks are ready under: ${WORKSPACE}"
echo "Next: configure the shared manifest base in operating-system and supervisor."
