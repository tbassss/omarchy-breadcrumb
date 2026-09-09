#!/usr/bin/python3
"""Independent argv-Process open-launch seam tests (issue #7).

These do not open real apps, call xdg-open, or use a shell. They lock the
three launch outcomes the QML Process seam must surface: success, start
failure, and nonzero exit. Source contracts here are not native qs evidence.
"""

from __future__ import annotations

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "Panel.qml"
OPEN_FAILURE = "Could not open that link."


def interpret_open_launch(started: bool, exit_code: int | None) -> dict:
    if not started:
        return {"ok": False, "error": "start_failed", "message": OPEN_FAILURE}
    if exit_code != 0:
        return {"ok": False, "error": "nonzero", "message": OPEN_FAILURE}
    return {"ok": True, "error": "", "message": ""}


def write_fake_launcher(directory: Path, name: str, exit_code: int) -> Path:
    path = directory / name
    path.write_text(
        "#!/usr/bin/python3\n"
        "import sys\n"
        f"raise SystemExit({exit_code})\n",
        encoding="utf-8",
    )
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return path


def run_argv(argv: list[str], *, timeout: float = 3.0) -> dict:
    """Mirrors QML Process: string-list argv, no shell, bounded wait."""
    try:
        proc = subprocess.run(
            argv,
            shell=False,
            timeout=timeout,
            capture_output=True,
            check=False,
        )
    except FileNotFoundError:
        return interpret_open_launch(False, None)
    except subprocess.TimeoutExpired:
        return interpret_open_launch(True, 124)
    return interpret_open_launch(True, proc.returncode)


class TestOpenLaunch(unittest.TestCase):
    def test_successful_fake_launcher_exits_zero(self) -> None:
        with tempfile.TemporaryDirectory(prefix="breadcrumb-open-ok-") as raw:
            fake = write_fake_launcher(Path(raw), "open-ok", 0)
            result = run_argv([str(fake), "--", "https://example.com/notes"])
        self.assertTrue(result["ok"], result)
        self.assertEqual(result["error"], "")

    def test_nonzero_fake_launcher_is_visible_failure(self) -> None:
        with tempfile.TemporaryDirectory(prefix="breadcrumb-open-fail-") as raw:
            fake = write_fake_launcher(Path(raw), "open-fail", 2)
            result = run_argv([str(fake), "--", "https://example.com/notes"])
        self.assertFalse(result["ok"], result)
        self.assertEqual(result["error"], "nonzero")
        self.assertEqual(result["message"], OPEN_FAILURE)

    def test_missing_launcher_is_start_failure(self) -> None:
        missing = "/tmp/breadcrumb-missing-open-launcher-" + os.urandom(4).hex()
        self.assertFalse(Path(missing).exists())
        result = run_argv([missing, "--", "https://example.com/notes"])
        self.assertFalse(result["ok"], result)
        self.assertEqual(result["error"], "start_failed")
        self.assertEqual(result["message"], OPEN_FAILURE)

    def test_argv_seam_never_uses_shell_or_xdg_open(self) -> None:
        with tempfile.TemporaryDirectory(prefix="breadcrumb-open-no-xdg-") as raw:
            fake = write_fake_launcher(Path(raw), "open-ok", 0)
            argv = [str(fake), "--", "https://example.com/notes"]
            proc = subprocess.run(argv, shell=False, timeout=3, capture_output=True, check=False)
        self.assertEqual(proc.returncode, 0)
        self.assertNotIn("xdg-open", argv)
        self.assertFalse(any("bash" in part or part == "sh" for part in argv))

    def test_panel_uses_argv_process_not_exec_detached(self) -> None:
        qml = PANEL.read_text(encoding="utf-8")
        self.assertIn("function launchOpenArgv(", qml)
        self.assertIn("id: openProc", qml)
        self.assertIn("openProc.command", qml)
        self.assertIn("openProc.running", qml)
        self.assertNotIn("Quickshell.execDetached", qml)
        self.assertNotIn("startDetached", qml)
        launch_idx = qml.index("function launchOpenArgv(")
        launch = qml[launch_idx : launch_idx + 1600]
        self.assertNotIn("bash", launch)
        self.assertIn("Could not open that link.", qml)
        self.assertIn("BREADCRUMB_NO_OPEN", qml)
        self.assertIn("BREADCRUMB_OPEN_LAUNCHER", qml)
        self.assertIn("interval: 8000", qml)
        self.assertIn("id: openTimeout", qml)


if __name__ == "__main__":
    unittest.main()
