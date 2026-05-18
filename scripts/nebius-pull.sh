#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Pull one run directory from the Nebius VM.

Usage:
  scripts/nebius-pull.sh <run-id> [notebook.ipynb]

If notebook.ipynb is provided, the pulled executed notebook is copied back
to that local notebook path after saving a backup in outputs/nebius/<run-id>/.
USAGE
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

config_file="${NEBIUS_CONFIG:-.env.nebius}"
if [[ -f "$config_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$config_file"
  set +a
fi

if [[ $# -ge 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

run_id="$1"
notebook="${2:-}"
: "${NEBIUS_HOST:?Set NEBIUS_HOST in .env.nebius or the command environment.}"
NEBIUS_USER="${NEBIUS_USER:-ubuntu}"
NEBIUS_PORT="${NEBIUS_PORT:-22}"
NEBIUS_REMOTE_DIR="${NEBIUS_REMOTE_DIR:-lm-arch-ht4}"

ssh_dest="${NEBIUS_USER}@${NEBIUS_HOST}"
rsync_rsh="ssh -p $NEBIUS_PORT"
if [[ -n "${NEBIUS_SSH_KEY:-}" ]]; then
  rsync_rsh="$rsync_rsh -i $NEBIUS_SSH_KEY"
fi

mkdir -p "outputs/nebius/${run_id}"
rsync -az -e "$rsync_rsh" \
  "${ssh_dest}:${NEBIUS_REMOTE_DIR}/outputs/nebius/${run_id}/" \
  "outputs/nebius/${run_id}/"

if [[ -n "$notebook" ]]; then
  if [[ ! -f "$notebook" ]]; then
    echo "Notebook not found: $notebook" >&2
    exit 1
  fi

  executed_name="$(basename "$notebook" .ipynb)-executed.ipynb"
  executed_notebook="outputs/nebius/${run_id}/${executed_name}"
  if [[ ! -f "$executed_notebook" ]]; then
    echo "Executed notebook was not found after pull: ${executed_notebook}" >&2
    exit 1
  fi

  backup_notebook="outputs/nebius/${run_id}/local-before-update-$(basename "$notebook")"
  cp "$notebook" "$backup_notebook"
  cp "$executed_notebook" "$notebook"
  echo "Updated local notebook with remote outputs: ${notebook}"
  echo "Previous local notebook backup: ${backup_notebook}"
fi

echo "Pulled: outputs/nebius/${run_id}/"
