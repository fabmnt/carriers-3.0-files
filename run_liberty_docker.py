#!/usr/bin/env python3
"""Run the Liberty Playwright bot inside the core Docker image."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


DEFAULT_IMAGE = "eloskar101/core:beta"
PROJECT_ROOT = Path(__file__).resolve().parent
DEFAULT_CONTEXT = PROJECT_ROOT / "context.json"
DEFAULT_CORE_SOURCE = Path(r"C:\Users\fabia\Dev\Work\playwright-core")
DEFAULT_RESULTS = Path(r"C:\Runner\Results")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run `pw run liberty --no-live` inside eloskar101/core:beta.",
    )
    parser.add_argument(
        "--image",
        default=DEFAULT_IMAGE,
        help=f"Docker image to run. Defaults to {DEFAULT_IMAGE}.",
    )
    parser.add_argument(
        "--context",
        type=Path,
        default=DEFAULT_CONTEXT,
        help=f"Context JSON to mount. Defaults to {DEFAULT_CONTEXT}.",
    )
    parser.add_argument(
        "--core-source",
        type=Path,
        default=DEFAULT_CORE_SOURCE,
        help="Local checkout containing the pw command source, mounted read-only for reference.",
    )
    parser.add_argument(
        "--results",
        type=Path,
        default=DEFAULT_RESULTS,
        help=f"Host results folder to mount at /app/reports. Defaults to {DEFAULT_RESULTS}.",
    )
    parser.add_argument(
        "playwright_args",
        nargs=argparse.REMAINDER,
        help="Optional args forwarded after `pw run liberty --no-live`.",
    )
    return parser.parse_args()


def docker_mount_path(path: Path) -> str:
    return str(path.resolve())


def main() -> int:
    args = parse_args()
    context_path = args.context.resolve()
    core_source = args.core_source.resolve()
    results_path = args.results.resolve()

    if not context_path.is_file():
        print(f"Context file not found: {context_path}", file=sys.stderr)
        return 2

    if not core_source.is_dir():
        print(f"pw source directory not found: {core_source}", file=sys.stderr)
        return 2

    results_path.mkdir(parents=True, exist_ok=True)

    subprocess.run(["docker", "pull", args.image], check=True)

    command = ["pw", "run", "liberty", "--no-live", *args.playwright_args]
    docker_args = [
        "docker",
        "run",
        "--rm",
        "-v",
        f"{docker_mount_path(context_path)}:/app/context/context.json:ro",
        "-v",
        f"{docker_mount_path(core_source)}:/pw-source:ro",
        "-v",
        f"{docker_mount_path(results_path)}:/app/reports",
        "-e",
        "REPORTS_PATH=/app/reports",
        "-w",
        "/app",
    ]

    if sys.stdin.isatty() and sys.stdout.isatty():
        docker_args.append("-it")

    docker_args.extend([args.image, *command])

    print("Running:", " ".join(docker_args))
    return subprocess.run(docker_args, env=os.environ.copy()).returncode


if __name__ == "__main__":
    raise SystemExit(main())
