#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Run a local notebook on a Nebius VM.

Usage:
  scripts/nebius-run.sh [--no-sync] [--no-pull] [--no-update-notebook] <notebook.ipynb>

Config:
  Copy scripts/nebius.env.example to .env.nebius and set NEBIUS_HOST.
  Set NEBIUS_EXEC_MODE=jupyter to use the existing Jupyter environment on the VM.
  You can also set NEBIUS_CONFIG=/path/to/env-file.

Examples:
  scripts/nebius-run.sh notebooks/tiny_moe_lm.ipynb
  NEBIUS_HOST=1.2.3.4 scripts/nebius-run.sh notebooks/tiny_moe_lm_nebius_calc.ipynb
  scripts/nebius-run.sh --no-update-notebook notebooks/tiny_moe_lm.ipynb
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

no_sync=0
no_pull=0
update_notebook=1
notebook=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-sync)
      no_sync=1
      shift
      ;;
    --no-pull)
      no_pull=1
      shift
      ;;
    --no-update-notebook)
      update_notebook=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      notebook="$1"
      shift
      ;;
  esac
done

if [[ -z "$notebook" ]]; then
  usage >&2
  exit 2
fi

if [[ ! -f "$notebook" ]]; then
  echo "Notebook not found: $notebook" >&2
  exit 1
fi

: "${NEBIUS_HOST:?Set NEBIUS_HOST in .env.nebius or the command environment.}"
NEBIUS_USER="${NEBIUS_USER:-ubuntu}"
NEBIUS_PORT="${NEBIUS_PORT:-22}"
NEBIUS_REMOTE_DIR="${NEBIUS_REMOTE_DIR:-lm-arch-ht4}"
NEBIUS_REMOTE_VENV="${NEBIUS_REMOTE_VENV:-.venv}"
NEBIUS_EXEC_MODE="${NEBIUS_EXEC_MODE:-jupyter}"
NEBIUS_JUPYTER_PYTHON="${NEBIUS_JUPYTER_PYTHON:-python}"

ssh_dest="${NEBIUS_USER}@${NEBIUS_HOST}"
ssh_args=(-p "$NEBIUS_PORT")
if [[ -n "${NEBIUS_SSH_KEY:-}" ]]; then
  ssh_args+=(-i "$NEBIUS_SSH_KEY")
fi

rsync_rsh="ssh -p $NEBIUS_PORT"
if [[ -n "${NEBIUS_SSH_KEY:-}" ]]; then
  rsync_rsh="$rsync_rsh -i $NEBIUS_SSH_KEY"
fi

run_id="${NEBIUS_RUN_ID:-$(date +%Y%m%d_%H%M%S)-$(basename "$notebook" .ipynb)}"
executed_name="$(basename "$notebook" .ipynb)-executed.ipynb"

if [[ "$no_sync" -eq 0 ]]; then
  echo "Syncing project to ${ssh_dest}:${NEBIUS_REMOTE_DIR}/"
  ssh "${ssh_args[@]}" "$ssh_dest" "mkdir -p $(printf '%q' "$NEBIUS_REMOTE_DIR")"
  rsync -az --delete \
    --exclude ".git/" \
    --exclude ".venv/" \
    --exclude "__pycache__/" \
    --exclude ".ipynb_checkpoints/" \
    --exclude ".env" \
    --exclude ".env.*" \
    --exclude "data/" \
    --exclude "outputs/" \
    --exclude "runs/" \
    --exclude "checkpoints/" \
    --exclude "wandb/" \
    --exclude "*.pt" \
    --exclude "*.pth" \
    --exclude "*.ckpt" \
    -e "$rsync_rsh" \
    ./ "${ssh_dest}:${NEBIUS_REMOTE_DIR}/"
fi

remote_dir_q="$(printf '%q' "$NEBIUS_REMOTE_DIR")"
remote_venv_q="$(printf '%q' "$NEBIUS_REMOTE_VENV")"
exec_mode_q="$(printf '%q' "$NEBIUS_EXEC_MODE")"
jupyter_python_q="$(printf '%q' "$NEBIUS_JUPYTER_PYTHON")"
notebook_q="$(printf '%q' "$notebook")"
run_id_q="$(printf '%q' "$run_id")"

echo "Running ${notebook} on ${ssh_dest} as run ${run_id}"
set +e
ssh "${ssh_args[@]}" "$ssh_dest" \
  "cd ${remote_dir_q} && NEBIUS_REMOTE_VENV=${remote_venv_q} NEBIUS_EXEC_MODE=${exec_mode_q} NEBIUS_JUPYTER_PYTHON=${jupyter_python_q} bash scripts/nebius-remote-run.sh ${notebook_q} ${run_id_q}"
remote_status=$?
set -e

if [[ "$no_pull" -eq 0 ]]; then
  mkdir -p "outputs/nebius/${run_id}"
  echo "Pulling remote outputs to outputs/nebius/${run_id}/"
  rsync -az -e "$rsync_rsh" \
    "${ssh_dest}:${NEBIUS_REMOTE_DIR}/outputs/nebius/${run_id}/" \
    "outputs/nebius/${run_id}/"

  if [[ "$update_notebook" -eq 1 && "$remote_status" -eq 0 ]]; then
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
  elif [[ "$update_notebook" -eq 1 ]]; then
    echo "Remote run failed; pulled logs but did not update local notebook."
  fi
elif [[ "$update_notebook" -eq 1 ]]; then
  echo "Skipping local notebook update because --no-pull was used."
fi

echo "Done: outputs/nebius/${run_id}/"
exit "$remote_status"
