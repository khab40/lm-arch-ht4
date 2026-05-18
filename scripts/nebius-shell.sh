#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

config_file="${NEBIUS_CONFIG:-.env.nebius}"
if [[ -f "$config_file" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$config_file"
  set +a
fi

: "${NEBIUS_HOST:?Set NEBIUS_HOST in .env.nebius or the command environment.}"
NEBIUS_USER="${NEBIUS_USER:-ubuntu}"
NEBIUS_PORT="${NEBIUS_PORT:-22}"
NEBIUS_REMOTE_DIR="${NEBIUS_REMOTE_DIR:-lm-arch-ht4}"
NEBIUS_EXEC_MODE="${NEBIUS_EXEC_MODE:-jupyter}"

ssh_args=(-p "$NEBIUS_PORT")
if [[ -n "${NEBIUS_SSH_KEY:-}" ]]; then
  ssh_args+=(-i "$NEBIUS_SSH_KEY")
fi

ssh "${ssh_args[@]}" -t "${NEBIUS_USER}@${NEBIUS_HOST}" \
  "cd $(printf '%q' "$NEBIUS_REMOTE_DIR") 2>/dev/null || cd; echo \"Connected to VM/Jupyter environment: \$(hostname):\$(pwd)\"; exec bash -l"
