#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: scripts/nebius-remote-run.sh <notebook.ipynb> <run-id>" >&2
  exit 2
fi

notebook="$1"
run_id="$2"
venv_dir="${NEBIUS_REMOTE_VENV:-.venv}"
python_bin="${NEBIUS_PYTHON:-python3}"
exec_mode="${NEBIUS_EXEC_MODE:-jupyter}"
jupyter_python="${NEBIUS_JUPYTER_PYTHON:-python}"
out_dir="outputs/nebius/${run_id}"

if [[ ! -f "$notebook" ]]; then
  echo "Notebook not found on remote: $notebook" >&2
  exit 1
fi

mkdir -p "$out_dir"

if [[ "$exec_mode" == "jupyter" ]]; then
  executed_name="$(basename "$notebook" .ipynb)-executed.ipynb"

  {
    echo "run_id=${run_id}"
    echo "notebook=${notebook}"
    echo "exec_mode=jupyter"
    echo "jupyter_python=${jupyter_python}"
    echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host=$(hostname)"
    echo "pwd=$(pwd)"
    echo "python=$("${jupyter_python}" -c 'import sys; print(sys.executable)' 2>/dev/null || echo unavailable)"
    if command -v nvidia-smi >/dev/null 2>&1; then
      echo
      nvidia-smi
    else
      echo
      echo "nvidia-smi not found"
    fi
  } | tee "${out_dir}/run-info.txt"

  if ! "${jupyter_python}" -m jupyter --version >/dev/null 2>&1; then
    echo "Jupyter is not available through NEBIUS_JUPYTER_PYTHON=${jupyter_python}" | tee -a "${out_dir}/run-info.txt" >&2
    echo "Set NEBIUS_JUPYTER_PYTHON to the Python executable used by the running Jupyter environment." | tee -a "${out_dir}/run-info.txt" >&2
    exit 1
  fi

  set +e
  "${jupyter_python}" -m jupyter nbconvert \
    --to notebook \
    --execute "$notebook" \
    --output "$executed_name" \
    --output-dir "$out_dir" \
    --ExecutePreprocessor.timeout=-1 \
    2>&1 | tee "${out_dir}/nbconvert.log"
  status=${PIPESTATUS[0]}
  set -e

  {
    echo
    echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "exit_status=${status}"
  } | tee -a "${out_dir}/run-info.txt"

  exit "$status"
fi

if [[ "$exec_mode" != "host" ]]; then
  echo "Unsupported NEBIUS_EXEC_MODE=${exec_mode}. Use jupyter or host." >&2
  exit 2
fi

{
  echo "run_id=${run_id}"
  echo "notebook=${notebook}"
  echo "exec_mode=host"
  echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "host=$(hostname)"
  echo "pwd=$(pwd)"
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo
    nvidia-smi
  else
    echo
    echo "nvidia-smi not found"
  fi
} | tee "${out_dir}/run-info.txt"

if [[ ! -x "${venv_dir}/bin/python" ]]; then
  "$python_bin" -m venv "$venv_dir"
fi

"${venv_dir}/bin/python" -m pip install --upgrade pip wheel setuptools
"${venv_dir}/bin/python" -m pip install -r requirements.txt

executed_name="$(basename "$notebook" .ipynb)-executed.ipynb"

set +e
"${venv_dir}/bin/jupyter" nbconvert \
  --to notebook \
  --execute "$notebook" \
  --output "$executed_name" \
  --output-dir "$out_dir" \
  --ExecutePreprocessor.timeout=-1 \
  2>&1 | tee "${out_dir}/nbconvert.log"
status=${PIPESTATUS[0]}
set -e

{
  echo
  echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "exit_status=${status}"
} | tee -a "${out_dir}/run-info.txt"

exit "$status"
