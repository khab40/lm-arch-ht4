# Local Editing + Nebius Remote Runs

Use this workflow when you want to edit notebooks locally with Codex and run the heavy GPU experiments on a Nebius VM whose public IP may change between experiments.

## One-Time Local Setup

Create a local config file from the tracked template:

```bash
cp scripts/nebius.env.example .env.nebius
```

Edit `.env.nebius` for the current VM:

```bash
NEBIUS_HOST=<current-public-ip>
NEBIUS_USER=khab1973
NEBIUS_PORT=22
NEBIUS_SSH_KEY=$HOME/.ssh/nebius
NEBIUS_REMOTE_DIR=lm-arch-ht4

# Use the already-configured Jupyter/Python environment on the VM.
NEBIUS_EXEC_MODE=jupyter
NEBIUS_JUPYTER_PYTHON=python
```

`.env.nebius` is ignored by git, so you can change `NEBIUS_HOST` for each VM without touching the repository.

Check that the SSH session sees the same Python/Jupyter environment:

```bash
ssh khab1973@<current-public-ip> 'python -c "import sys; print(sys.executable)" && python -m jupyter --version'
```

If the Jupyter environment uses a different Python executable, set it explicitly:

```bash
NEBIUS_JUPYTER_PYTHON=/path/to/jupyter/env/bin/python
```

## Run a Notebook Remotely

From the repo root:

```bash
scripts/nebius-run.sh notebooks/tiny_moe_lm.ipynb
```

For the Nebius-specific notebook:

```bash
scripts/nebius-run.sh notebooks/tiny_moe_lm_nebius_calc.ipynb
```

The launcher does four things:

1. syncs the local project to the VM with `rsync`,
2. executes the notebook through the already-configured Jupyter/Python environment with `jupyter nbconvert`,
3. stores the executed notebook and logs on the VM,
4. pulls the executed notebook and logs back to your machine,
5. copies the executed notebook back over the local notebook so conclusions can be written next to the real remote outputs.

The older direct-host mode is still available. Use it only if you want the script to create a VM-host `.venv`:

```bash
NEBIUS_EXEC_MODE=host
NEBIUS_REMOTE_VENV=.venv
```

Results are pulled back to:

```text
outputs/nebius/<run-id>/
```

Each run directory contains:

- `run-info.txt` with host, time, and GPU details,
- `nbconvert.log`,
- the executed notebook.
- `local-before-update-<notebook>.ipynb`, a backup of the local notebook before remote outputs were copied into it.

After a successful run, the original local notebook path, for example `notebooks/tiny_moe_lm.ipynb`, contains the remote execution outputs. This is intentional: use that notebook to write conclusions supported by the measured GPU run.

If the remote notebook fails, the launcher still pulls `run-info.txt` and `nbconvert.log` when possible, but it does not overwrite the local notebook.

## Useful Variants

Use a changing IP without editing `.env.nebius`:

```bash
NEBIUS_HOST=<new-public-ip> scripts/nebius-run.sh notebooks/tiny_moe_lm.ipynb
```

Run without re-syncing the project:

```bash
scripts/nebius-run.sh --no-sync notebooks/tiny_moe_lm.ipynb
```

Run without pulling outputs immediately:

```bash
scripts/nebius-run.sh --no-pull notebooks/tiny_moe_lm.ipynb
```

Run without replacing the local notebook:

```bash
scripts/nebius-run.sh --no-update-notebook notebooks/tiny_moe_lm.ipynb
```

Pull a run later:

```bash
scripts/nebius-pull.sh <run-id>
```

Pull a run later and copy the executed notebook back into the local notebook:

```bash
scripts/nebius-pull.sh <run-id> notebooks/tiny_moe_lm.ipynb
```

Open a shell on the VM in the remote project directory:

```bash
scripts/nebius-shell.sh
```

## Recommended Working Loop

1. Edit locally in this repo with Codex.
2. Keep all source changes in notebooks, `src/`, docs, and scripts.
3. Set or override `NEBIUS_HOST` for the current VM.
4. Run the notebook remotely with `scripts/nebius-run.sh`.
5. Review the updated local notebook for outputs, metrics, plots, and generated samples.
6. Review the archived executed notebook and logs in `outputs/nebius/<run-id>/`.

Large generated artifacts are intentionally not synced from local to remote. Remote outputs are pulled back per run.
