# type: ignore
"""
Execution sandbox.

Provides secure, isolated execution of LLM-generated Python code inside a
dedicated Docker container with:
- Read-only bind mounts for every tabular file in the workspace
- Full network isolation (network_mode="none")
- Hard memory and CPU limits
- Non-root user execution
- Hard execution timeouts
"""
from __future__ import annotations

import json
import logging
import os
import re
import shutil
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import docker
from docker.errors import DockerException, ImageNotFound, NotFound
import requests

from config import settings

logger = logging.getLogger(__name__)


@dataclass
class ExecutionResult:
    success: bool
    result: Any = None
    stdout: str = ""
    error: str | None = None
    traceback: str | None = None
    plotly_json: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)


# In-container runner harness script.
# Executed inside the container to run user code in a unified scope,
# capture standard output, handle exceptions, and serialize the result.
_RUNNER_SCRIPT = """\
import contextlib
import io
import json
import sys
import traceback

output_file = "/workspace/output.json"
script_file = "/workspace/script.py"

# {original filename: container path} for every dataset mounted under /data
with open("/workspace/files.json", "r", encoding="utf-8") as f:
    files = json.load(f)

# Pre-populate common analytics modules so scripts function even if
# the LLM omits import statements.
execution_namespace = {
    "__name__": "__main__",
    "__file__": script_file,
    "files": files,
    # Convenience alias for single-dataset scripts: the first mounted file.
    "file_path": next(iter(files.values()), None),
}

for mod_name, alias in [("pandas", "pd"), ("plotly.express", "px"), ("plotly.graph_objects", "go"), ("numpy", "np")]:
    try:
        mod = __import__(mod_name, fromlist=["*"])
        execution_namespace[alias] = mod
    except ImportError:
        pass

stdout_buffer = io.StringIO()

try:
    with open(script_file, "r", encoding="utf-8") as f:
        code_str = f.read()

    compiled_code = compile(code_str, script_file, "exec")

    # Pass execution_namespace as BOTH globals and locals.
    # This prevents Python list-comprehension scope resolution bugs.
    with contextlib.redirect_stdout(stdout_buffer):
        exec(compiled_code, execution_namespace, execution_namespace)

    stdout_content = stdout_buffer.getvalue()
    result_val = execution_namespace.get("result")
    fig_val = execution_namespace.get("fig")

    plotly_json = None
    if fig_val is not None and hasattr(fig_val, "to_json"):
        try:
            plotly_json = fig_val.to_json()
        except Exception:
            pass

    # Drop a `result` that is just the figure serialized again.
    if plotly_json is not None and isinstance(result_val, str) and result_val == plotly_json:
        result_val = None

    if result_val is None and plotly_json is None:
        raise ValueError("Script did not assign a `result` or `fig` variable.")

    def _json_serializable(obj):
        if hasattr(obj, "to_dict"):
            return obj.to_dict()
        if hasattr(obj, "tolist"):
            return obj.tolist()
        if hasattr(obj, "item"):
            return obj.item()
        return str(obj)

    payload = {
        "success": True,
        "result": result_val,
        "stdout": stdout_content,
        "plotly_json": plotly_json,
        "error": None,
        "traceback": None,
    }
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(payload, f, default=_json_serializable)

except Exception as exc:
    stdout_content = stdout_buffer.getvalue()
    payload = {
        "success": False,
        "result": None,
        "stdout": stdout_content,
        "error": f"{type(exc).__name__}: {exc}",
        "traceback": traceback.format_exc(),
        "plotly_json": None,
    }
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(payload, f)
    sys.exit(1)
"""


def _get_docker_client() -> docker.DockerClient:
    try:
        return docker.from_env()
    except DockerException as exc:
        raise RuntimeError(
            f"Unable to connect to Docker daemon. Ensure Docker is running. Error: {exc}"
        ) from exc


def container_path_for(filename: str) -> str:
    """Where a dataset is mounted inside the sandbox. Kept deterministic so the
    Coder prompt and the mounts always agree."""
    stem = re.sub(r"[^A-Za-z0-9_.-]", "_", Path(filename).stem)
    return f"/data/{stem}.csv"


def execute_code_in_docker(
    script: str, files: dict[str, str], timeout_seconds: int = 30
) -> ExecutionResult:
    """Executes generated python code inside a network-isolated Docker container.

    `files` maps each dataset's original filename to its cleaned CSV on the host.
    """
    if not files:
        return ExecutionResult(success=False, error="No tabular datasets were provided to the sandbox.")

    mounts: dict[str, str] = {}  # host path -> container path
    container_files: dict[str, str] = {}  # original filename -> container path
    for filename, host_path in files.items():
        host_csv_path = Path(host_path).resolve()
        if not host_csv_path.exists():
            return ExecutionResult(
                success=False,
                error=f"Dataset file does not exist at path: {host_path}",
            )
        target = container_path_for(filename)
        if target in mounts.values():
            return ExecutionResult(success=False, error=f"Two datasets map to the same sandbox path: {target}")
        mounts[str(host_csv_path)] = target
        container_files[filename] = target

    try:
        client = _get_docker_client()
    except RuntimeError as exc:
        return ExecutionResult(success=False, error=str(exc))

    image_name = getattr(settings, "SANDBOX_DOCKER_IMAGE", "myanalyst-sandbox:latest")

    # Create temporary directory on the host to share script and outputs
    settings.DATA_DIR.mkdir(parents=True, exist_ok=True)
    temp_dir = tempfile.mkdtemp(prefix="myanalyst_sandbox_", dir=settings.DATA_DIR)

    container = None

    try:
        # Set workspace directory permissions to world-writable so a non-root
        # container user (UID 1000 / nobody) can create and write output.json
        os.chmod(temp_dir, 0o777)

        script_path = Path(temp_dir) / "script.py"
        runner_path = Path(temp_dir) / "runner.py"
        output_path = Path(temp_dir) / "output.json"

        script_path.write_text(script, encoding="utf-8")
        runner_path.write_text(_RUNNER_SCRIPT, encoding="utf-8")
        (Path(temp_dir) / "files.json").write_text(json.dumps(container_files), encoding="utf-8")

        # Mount specifications:
        # - each host CSV file is mounted read-only under /data
        # - host temp directory is mounted read-write at /workspace
        volumes = {host: {"bind": target, "mode": "ro,z"} for host, target in mounts.items()}
        volumes[str(Path(temp_dir).resolve())] = {"bind": "/workspace", "mode": "rw,z"}

        mem_limit = getattr(settings, "SANDBOX_MEM_LIMIT", "512m")
        nano_cpus = getattr(settings, "SANDBOX_NANO_CPUS", 1_000_000_000)  # 1.0 CPU

        try:
            container = client.containers.create(
                image=image_name,
                command=["python", "/workspace/runner.py"],
                network_mode="none",
                mem_limit=mem_limit,
                nano_cpus=nano_cpus,
                user="1000:1000",
                volumes=volumes,
                cap_drop=["ALL"],
                security_opt=["no-new-privileges:true"],
                working_dir="/workspace",
                detach=True,
            )
        except ImageNotFound:
            return ExecutionResult(
                success=False,
                error=(
                    f"Docker image '{image_name}' not found. "
                    "Build it using: docker build -t myanalyst-sandbox:latest -f Dockerfile.sandbox ."
                ),
            )

        container.start()

        try:
            # Enforce hard container timeout via socket read timeout
            res = container.wait(timeout=timeout_seconds)
            exit_code = res.get("StatusCode", 0) if isinstance(res, dict) else res
        except (requests.exceptions.ReadTimeout, requests.exceptions.ConnectionError):
            try:
                container.kill()
            except Exception:
                pass
            return ExecutionResult(
                success=False,
                error=f"Execution timed out after {timeout_seconds} seconds.",
                traceback=f"TimeoutError: Execution exceeded {timeout_seconds}s limit.",
            )

        # Inspect if container was killed due to memory limits (OOM)
        container.reload()
        state = container.attrs.get("State", {})
        if state.get("OOMKilled", False) or exit_code == 137:
            return ExecutionResult(
                success=False,
                error=f"Memory limit exceeded ({mem_limit}). The analysis was terminated.",
                traceback="MemoryError: Container killed by Docker OOM killer.",
            )

        # Parse results generated by runner.py
        if output_path.exists():
            try:
                data = json.loads(output_path.read_text(encoding="utf-8"))
                return ExecutionResult(
                    success=data.get("success", False),
                    result=data.get("result"),
                    stdout=data.get("stdout", ""),
                    error=data.get("error"),
                    traceback=data.get("traceback"),
                    plotly_json=data.get("plotly_json"),
                )
            except json.JSONDecodeError as exc:
                return ExecutionResult(
                    success=False,
                    error=f"Failed to parse container output JSON: {exc}",
                )

        # Fallback to container logs if runner.py terminated prematurely
        logs = container.logs(stdout=True, stderr=True).decode("utf-8", errors="replace")
        return ExecutionResult(
            success=False,
            stdout=logs,
            error=f"Container terminated unexpectedly with code {exit_code}.",
            traceback=logs,
        )

    except Exception as exc:
        logger.exception("Sandbox container execution error")
        return ExecutionResult(
            success=False,
            error=f"Sandbox execution error: {type(exc).__name__}: {exc}",
        )

    finally:
        if container is not None:
            try:
                container.remove(force=True)
            except (NotFound, DockerException):
                pass
        shutil.rmtree(temp_dir, ignore_errors=True)