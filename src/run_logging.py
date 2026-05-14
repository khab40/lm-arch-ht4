from __future__ import annotations

import logging
import sys
import time
from contextlib import contextmanager
from typing import Iterator


def configure_logging(name: str = "lm_arch", level: int = logging.INFO) -> logging.Logger:
    """Return a notebook-friendly logger without duplicate stream handlers."""
    logger = logging.getLogger(name)
    logger.setLevel(level)
    logger.propagate = False

    if not any(getattr(handler, "_lm_arch_handler", False) for handler in logger.handlers):
        handler = logging.StreamHandler(sys.stdout)
        handler._lm_arch_handler = True
        handler.setFormatter(
            logging.Formatter(
                fmt="%(asctime)s | %(levelname)s | %(message)s",
                datefmt="%H:%M:%S",
            )
        )
        logger.addHandler(handler)

    return logger


def format_duration(seconds: float) -> str:
    """Format elapsed seconds as a compact human-readable duration."""
    seconds = max(0.0, float(seconds))
    if seconds < 60:
        return f"{seconds:.1f}s"

    minutes, rem = divmod(int(round(seconds)), 60)
    if minutes < 60:
        return f"{minutes}m {rem:02d}s"

    hours, minutes = divmod(minutes, 60)
    return f"{hours}h {minutes:02d}m {rem:02d}s"


def now() -> float:
    """Monotonic timestamp for elapsed-time measurements."""
    return time.perf_counter()


@contextmanager
def timed_section(
    label: str,
    logger: logging.Logger | None = None,
    *,
    log_start: bool = True,
) -> Iterator[float]:
    """Log start/end messages for a block and yield its start timestamp."""
    active_logger = logger or configure_logging()
    start = now()
    if log_start:
        active_logger.info("%s | start", label)
    try:
        yield start
    finally:
        active_logger.info("%s | done in %s", label, format_duration(now() - start))


def log_step(
    logger: logging.Logger,
    label: str,
    step: int,
    *,
    total: int | None = None,
    start_time: float | None = None,
    **metrics: float | int | str,
) -> None:
    """Log progress for long loops, including elapsed time and ETA when possible."""
    parts = [label, f"step {step}"]
    if total is not None:
        parts[-1] = f"step {step}/{total}"

    if start_time is not None:
        elapsed = now() - start_time
        parts.append(f"elapsed {format_duration(elapsed)}")
        if total is not None and step > 0:
            eta = elapsed * max(total - step, 0) / step
            parts.append(f"eta {format_duration(eta)}")

    for key, value in metrics.items():
        if isinstance(value, float):
            parts.append(f"{key} {value:.4g}")
        else:
            parts.append(f"{key} {value}")

    logger.info(" | ".join(parts))
