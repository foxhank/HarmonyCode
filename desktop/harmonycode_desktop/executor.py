"""Runs commands for a paired phone: the desktop's shell, output streamed, whole process tree killable."""
from __future__ import annotations

import asyncio
import os
import signal
import subprocess
import sys
from typing import Awaitable, Callable

IS_WINDOWS = sys.platform == "win32"


def shell_name() -> str:
    return "PowerShell" if IS_WINDOWS else os.environ.get("SHELL", "/bin/sh")


def _argv(command: str) -> list[str]:
    if IS_WINDOWS:
        prelude = "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); $ProgressPreference = 'SilentlyContinue'; "
        return ["powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                "-Command", prelude + command]
    return ["/bin/sh", "-c", command]


class Running:
    """One command started by a phone."""

    def __init__(self, proc: asyncio.subprocess.Process) -> None:
        self.proc = proc
        self.killed = False

    def kill(self) -> None:
        if self.proc.returncode is not None:
            return
        self.killed = True
        try:
            if IS_WINDOWS:
                subprocess.run(["taskkill", "/PID", str(self.proc.pid), "/T", "/F"], capture_output=True)
            else:
                os.killpg(self.proc.pid, signal.SIGKILL)
        except (OSError, ProcessLookupError):
            pass


async def run(command: str, cwd: str, timeout_s: float, on_output: Callable[[bytes], Awaitable[None]],
              started: Callable[[Running], None]) -> tuple[int, bool]:
    """Runs to completion (or timeout). Returns (exit code, timed out)."""
    kwargs = {}
    if IS_WINDOWS:
        kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
    else:
        kwargs["start_new_session"] = True  # own process group, so kill reaches children
    proc = await asyncio.create_subprocess_exec(
        *_argv(command), cwd=cwd, stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT, **kwargs)
    job = Running(proc)
    started(job)
    timed_out = False

    async def pump() -> None:
        assert proc.stdout is not None
        while True:
            chunk = await proc.stdout.read(16384)
            if not chunk:
                break
            await on_output(chunk)

    try:
        await asyncio.wait_for(pump(), timeout=timeout_s if timeout_s > 0 else None)
    except asyncio.TimeoutError:
        timed_out = True
        job.kill()
    code = await proc.wait()
    return (-1 if timed_out else code), timed_out
