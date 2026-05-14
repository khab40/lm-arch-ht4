from __future__ import annotations
import torch

def choose_device() -> torch.device:
    """Return the best available PyTorch device: CUDA, then MPS, then CPU."""
    if torch.cuda.is_available():
        return torch.device("cuda")

    if torch.backends.mps.is_available():
        return torch.device("mps")

    return torch.device("cpu")

