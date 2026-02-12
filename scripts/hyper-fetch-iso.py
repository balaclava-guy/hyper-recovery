#!/usr/bin/env python3
"""
Download, extract, and copy a CI ISO artifact to a destination directory.

Defaults target the Hyper Recovery GitHub Actions workflow and Ventoy mount.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path
from typing import Any


DEFAULT_REPO = "balaclava-guy/hyper-recovery"
DEFAULT_WORKFLOW = "build.yml"
DEFAULT_ARTIFACT = "live-iso"
DEFAULT_DEST = "/Volumes/Ventoy"


def run_json(cmd: list[str]) -> Any:
    proc = subprocess.run(cmd, check=True, text=True, capture_output=True)
    return json.loads(proc.stdout)


def run_text(cmd: list[str]) -> str:
    proc = subprocess.run(cmd, check=True, text=True, capture_output=True)
    return proc.stdout.strip()


def run_to_file(cmd: list[str], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as fh:
        subprocess.run(cmd, check=True, stdout=fh)


def ensure_tools() -> None:
    for tool in ("gh",):
        if shutil.which(tool) is None:
            raise RuntimeError(f"Required tool '{tool}' not found in PATH")
    if shutil.which("7zz") is None and shutil.which("7z") is None:
        raise RuntimeError("Required extractor not found: expected '7zz' or '7z' in PATH")


def get_last_commit_sha() -> str:
    return run_text(["git", "rev-parse", "HEAD"])


def get_run(repo: str, run_id: int) -> dict[str, Any]:
    return run_json(
        [
            "gh",
            "run",
            "view",
            str(run_id),
            "-R",
            repo,
            "--json",
            "databaseId,status,conclusion,headSha,url,createdAt",
        ]
    )


def list_runs(repo: str, workflow: str, limit: int) -> list[dict[str, Any]]:
    return run_json(
        [
            "gh",
            "run",
            "list",
            "-R",
            repo,
            "-w",
            workflow,
            "--limit",
            str(limit),
            "--json",
            "databaseId,status,conclusion,headSha,url,createdAt",
        ]
    )


def wait_for_successful_run(
    repo: str,
    workflow: str,
    sha_prefix: str | None,
    run_id: int | None,
    watch: bool,
    poll_interval: int,
    timeout_seconds: int,
    limit: int,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds

    while True:
        if run_id is not None:
            run = get_run(repo, run_id)
            status = run.get("status")
            conclusion = run.get("conclusion")
            if status == "completed":
                if conclusion == "success":
                    return run
                raise RuntimeError(
                    f"Run {run_id} completed with conclusion='{conclusion}' (not success)"
                )
        else:
            for run in list_runs(repo, workflow, limit):
                if run.get("status") != "completed":
                    continue
                if run.get("conclusion") != "success":
                    continue
                head_sha = str(run.get("headSha", ""))
                if sha_prefix and not head_sha.startswith(sha_prefix):
                    continue
                return run

        if not watch:
            if run_id is not None:
                raise RuntimeError(
                    f"Run {run_id} is not completed successfully yet. Re-run with --watch."
                )
            qualifier = f" for sha prefix '{sha_prefix}'" if sha_prefix else ""
            raise RuntimeError(
                f"No successful completed run found{qualifier}. Re-run with --watch."
            )

        if time.monotonic() >= deadline:
            raise RuntimeError("Timed out waiting for successful workflow run")

        print("Waiting for successful workflow run...")
        time.sleep(poll_interval)


def get_artifacts_for_run(repo: str, run_id: int) -> list[dict[str, Any]]:
    data = run_json(
        [
            "gh",
            "api",
            f"repos/{repo}/actions/runs/{run_id}/artifacts",
        ]
    )
    return list(data.get("artifacts", []))


def wait_for_artifact(
    repo: str,
    run_id: int,
    artifact_name: str,
    watch: bool,
    poll_interval: int,
    timeout_seconds: int,
) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_seconds

    while True:
        for artifact in get_artifacts_for_run(repo, run_id):
            if artifact.get("name") != artifact_name:
                continue
            if artifact.get("expired"):
                raise RuntimeError(
                    f"Artifact '{artifact_name}' exists for run {run_id} but is expired"
                )
            return artifact

        if not watch:
            raise RuntimeError(
                f"Artifact '{artifact_name}' not available for run {run_id}. Re-run with --watch."
            )

        if time.monotonic() >= deadline:
            raise RuntimeError("Timed out waiting for artifact availability")

        print(f"Waiting for artifact '{artifact_name}' on run {run_id}...")
        time.sleep(poll_interval)


def extract_zip(zip_path: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(output_dir)


def extract_7z(archive_path: Path, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    extractor = "7zz" if shutil.which("7zz") is not None else "7z"
    subprocess.run(
        [extractor, "x", "-y", str(archive_path), f"-o{output_dir}"],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def pick_single_file(root: Path, pattern: str) -> Path:
    matches = sorted(root.rglob(pattern))
    if not matches:
        raise RuntimeError(f"No files matching '{pattern}' found under {root}")
    if len(matches) == 1:
        return matches[0]
    # Prefer the largest candidate if multiple are present.
    return max(matches, key=lambda p: p.stat().st_size)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=DEFAULT_REPO, help="GitHub repo in owner/name form")
    parser.add_argument("--workflow", default=DEFAULT_WORKFLOW, help="Workflow file name")
    parser.add_argument(
        "--artifact-name",
        default=DEFAULT_ARTIFACT,
        help="GitHub Actions artifact name",
    )
    parser.add_argument("--run-id", type=int, help="Use this specific run id")
    parser.add_argument("--sha", help="Find latest successful run for this commit SHA/prefix")
    parser.add_argument(
        "--last-commit",
        action="store_true",
        help="Use local git HEAD commit SHA as the run selector",
    )
    parser.add_argument(
        "--watch",
        action="store_true",
        help="Poll until run/artifact is available",
    )
    parser.add_argument(
        "--poll-interval",
        type=int,
        default=20,
        help="Polling interval in seconds when --watch is enabled",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=3600,
        help="Timeout in seconds when --watch is enabled",
    )
    parser.add_argument(
        "--run-list-limit",
        type=int,
        default=30,
        help="How many recent runs to inspect when selecting by SHA/latest",
    )
    parser.add_argument(
        "--dest",
        default=DEFAULT_DEST,
        help="Destination directory for final ISO copy",
    )
    parser.add_argument(
        "--workdir",
        help="Working directory (default: /tmp/hyper-iso-<run_id>)",
    )
    parser.add_argument(
        "--keep-workdir",
        action="store_true",
        help="Keep working directory after successful run",
    )
    parser.add_argument(
        "--no-verify",
        action="store_true",
        help="Skip SHA256 verification after copy",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    try:
        ensure_tools()

        if args.run_id is not None and (args.sha or args.last_commit):
            raise RuntimeError("Use either --run-id or --sha/--last-commit, not both")

        sha_prefix = args.sha
        if args.last_commit:
            sha_prefix = get_last_commit_sha()

        run = wait_for_successful_run(
            repo=args.repo,
            workflow=args.workflow,
            sha_prefix=sha_prefix,
            run_id=args.run_id,
            watch=args.watch,
            poll_interval=args.poll_interval,
            timeout_seconds=args.timeout,
            limit=args.run_list_limit,
        )
        selected_run_id = int(run["databaseId"])
        print(
            f"Selected run {selected_run_id} ({run.get('headSha', '')[:12]}) {run.get('url', '')}"
        )

        artifact = wait_for_artifact(
            repo=args.repo,
            run_id=selected_run_id,
            artifact_name=args.artifact_name,
            watch=args.watch,
            poll_interval=args.poll_interval,
            timeout_seconds=args.timeout,
        )
        artifact_id = int(artifact["id"])
        print(
            f"Using artifact '{args.artifact_name}' id={artifact_id} size={artifact.get('size_in_bytes')} bytes"
        )

        workdir = Path(args.workdir) if args.workdir else Path(f"/tmp/hyper-iso-{selected_run_id}")
        download_dir = workdir / "download"
        zip_extract_dir = workdir / "zip-extract"
        seven_extract_dir = workdir / "extract"
        workdir.mkdir(parents=True, exist_ok=True)

        zip_path = download_dir / f"{args.artifact_name}.zip"
        print(f"Downloading artifact zip to {zip_path}")
        run_to_file(
            [
                "gh",
                "api",
                f"repos/{args.repo}/actions/artifacts/{artifact_id}/zip",
            ],
            zip_path,
        )

        print(f"Extracting zip to {zip_extract_dir}")
        extract_zip(zip_path, zip_extract_dir)

        archive_7z = pick_single_file(zip_extract_dir, "*.7z")
        print(f"Extracting 7z archive {archive_7z} to {seven_extract_dir}")
        extract_7z(archive_7z, seven_extract_dir)

        iso_path = pick_single_file(seven_extract_dir, "*.iso")
        dest_dir = Path(args.dest)
        if not dest_dir.exists() or not dest_dir.is_dir():
            raise RuntimeError(f"Destination directory does not exist: {dest_dir}")
        dest_iso = dest_dir / iso_path.name

        print(f"Copying {iso_path} -> {dest_iso}")
        shutil.copy2(iso_path, dest_iso)

        if not args.no_verify:
            src_hash = sha256(iso_path)
            dst_hash = sha256(dest_iso)
            if src_hash != dst_hash:
                raise RuntimeError(
                    f"SHA256 mismatch after copy: src={src_hash} dst={dst_hash}"
                )
            print(f"SHA256 verified: {src_hash}")

        print(f"Done. ISO ready at: {dest_iso}")

        if not args.keep_workdir:
            shutil.rmtree(workdir, ignore_errors=True)
            print(f"Removed workdir: {workdir}")
        else:
            print(f"Kept workdir: {workdir}")

        return 0
    except subprocess.CalledProcessError as exc:
        print(f"Command failed (exit {exc.returncode}): {' '.join(exc.cmd)}", file=sys.stderr)
        return 1
    except Exception as exc:  # noqa: BLE001
        print(f"Error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
