#!/usr/bin/env python3
"""Behavioral tests for the Breadcrumb store CLI (issue #3)."""

from __future__ import annotations

import json
import os
import sqlite3
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "bin" / "breadcrumb-store"


def run_store(data_dir: Path, command: str, payload: dict | None = None, *, extra_env: dict | None = None, argv_json: bool = False) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["BREADCRUMB_DATA_DIR"] = str(data_dir)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    if extra_env:
        env.update(extra_env)
    cmd = [sys.executable, str(STORE), command]
    stdin = None
    if argv_json:
        cmd.append(json.dumps(payload or {}))
    else:
        stdin = json.dumps(payload or {})
    return subprocess.run(
        cmd,
        input=stdin,
        capture_output=True,
        text=True,
        env=env,
        timeout=15,
    )


def decode(proc: subprocess.CompletedProcess[str]) -> dict:
    if not proc.stdout.strip():
        return {"_empty": True, "stderr": proc.stderr, "returncode": proc.returncode}
    return json.loads(proc.stdout)


class TestStore(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="breadcrumb-test-")
        self.data_dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_ensure_activity_creates_private_dir_and_stable_uuid(self) -> None:
        proc = run_store(self.data_dir, "ensure-activity", {"name": "Study session"})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertTrue(body.get("ok"), body)
        activity = body["activity"]
        self.assertEqual(activity["name"], "Study session")
        self.assertRegex(activity["id"], r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        self.assertTrue(activity["created_at"].endswith("Z"))

        mode = stat.S_IMODE(self.data_dir.stat().st_mode)
        self.assertEqual(mode, 0o700)
        db = self.data_dir / "breadcrumb.sqlite"
        self.assertTrue(db.is_file())
        self.assertEqual(stat.S_IMODE(db.stat().st_mode), 0o600)

        again = run_store(self.data_dir, "ensure-activity", {"name": "Other name"})
        self.assertEqual(again.returncode, 0, again.stderr)
        again_body = decode(again)
        self.assertEqual(again_body["activity"]["id"], activity["id"])
        self.assertEqual(again_body["activity"]["name"], "Study session")

    def test_get_reports_empty_current_checkpoint(self) -> None:
        created = decode(run_store(self.data_dir, "ensure-activity", {"name": "Study session"}))
        proc = run_store(self.data_dir, "get", {})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["activity"]["id"], created["activity"]["id"])
        self.assertIsNone(body["current"])
        self.assertEqual(body["revision"], 0)
        self.assertEqual(body["view"], "compact")
        self.assertEqual(body["state"], "empty")

    def test_publish_persists_current_checkpoint_for_reopen(self) -> None:
        activity = decode(run_store(self.data_dir, "ensure-activity", {"name": "Study session"}))["activity"]
        payload = {
            "activity_id": activity["id"],
            "expected_revision": 0,
            "summary": "Reading chapter 3",
            "next_step": "Finish the practice problems",
            "context": "Fictional course notes only.",
            "state": "in_progress",
            "author": "You",
            "links": [
                {"label": "Spec", "kind": "web", "target": "https://example.com/spec"},
            ],
        }
        proc = run_store(self.data_dir, "publish", payload)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertTrue(body.get("ok"), body)
        current = body["current"]
        self.assertEqual(current["revision"], 1)
        self.assertEqual(current["summary"], "Reading chapter 3")
        self.assertEqual(current["next_step"], "Finish the practice problems")
        self.assertEqual(current["context"], "Fictional course notes only.")
        self.assertEqual(current["state"], "in_progress")
        self.assertEqual(current["author"], "You")
        self.assertEqual(current["links"], payload["links"])
        self.assertTrue(current["saved_at"].endswith("Z"))
        self.assertRegex(current["id"], r"^[0-9a-f-]{36}$")

        reopened = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertTrue(reopened.get("ok"), reopened)
        self.assertEqual(reopened["state"], "ready")
        self.assertEqual(reopened["revision"], 1)
        self.assertEqual(reopened["current"]["id"], current["id"])
        self.assertEqual(reopened["current"]["summary"], current["summary"])
        self.assertEqual(reopened["current"]["next_step"], current["next_step"])
        self.assertEqual(reopened["current"]["links"], payload["links"])

    def test_done_checkpoint_may_omit_next_step(self) -> None:
        activity = decode(run_store(self.data_dir, "ensure-activity", {"name": "Study session"}))["activity"]
        proc = run_store(
            self.data_dir,
            "publish",
            {
                "activity_id": activity["id"],
                "expected_revision": 0,
                "summary": "Chapter 3 complete",
                "state": "done",
                "author": "You",
            },
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["current"]["state"], "done")
        self.assertTrue(body["current"]["next_step"] in (None, ""))

        missing = run_store(
            self.data_dir,
            "publish",
            {
                "activity_id": activity["id"],
                "expected_revision": 1,
                "summary": "Still reading",
                "state": "in_progress",
                "author": "You",
            },
        )
        self.assertNotEqual(missing.returncode, 0)
        err = decode(missing)
        self.assertFalse(err.get("ok"))
        self.assertEqual(err["error"], "validation")
        unchanged = decode(run_store(self.data_dir, "get", {}))
        self.assertEqual(unchanged["current"]["state"], "done")
        self.assertEqual(unchanged["revision"], 1)

    def test_stale_revision_does_not_overwrite_or_report_success(self) -> None:
        activity = decode(run_store(self.data_dir, "ensure-activity", {"name": "Study session"}))["activity"]
        first = decode(
            run_store(
                self.data_dir,
                "publish",
                {
                    "activity_id": activity["id"],
                    "expected_revision": 0,
                    "summary": "First save",
                    "next_step": "Keep going",
                    "state": "ready",
                    "author": "You",
                },
            )
        )
        second = decode(
            run_store(
                self.data_dir,
                "publish",
                {
                    "activity_id": activity["id"],
                    "expected_revision": 1,
                    "summary": "Second save",
                    "next_step": "Write notes",
                    "state": "in_progress",
                    "author": "You",
                },
            )
        )
        stale = run_store(
            self.data_dir,
            "publish",
            {
                "activity_id": activity["id"],
                "expected_revision": 1,
                "summary": "Stale save",
                "next_step": "Should not land",
                "state": "waiting",
                "author": "You",
            },
        )
        self.assertNotEqual(stale.returncode, 0)
        err = decode(stale)
        self.assertFalse(err.get("ok"))
        self.assertEqual(err["error"], "stale_revision")
        self.assertEqual(err["current_revision"], 2)
        self.assertIn("Reload", err["message"])
        current = decode(run_store(self.data_dir, "get", {}))["current"]
        self.assertEqual(current["id"], second["current"]["id"])
        self.assertEqual(current["summary"], "Second save")
        self.assertNotEqual(current["id"], first["current"]["id"])

    def test_rejects_unsafe_links_and_keeps_prior_checkpoint(self) -> None:
        activity = decode(run_store(self.data_dir, "ensure-activity", {"name": "Study session"}))["activity"]
        good = decode(
            run_store(
                self.data_dir,
                "publish",
                {
                    "activity_id": activity["id"],
                    "expected_revision": 0,
                    "summary": "Safe notes",
                    "next_step": "Open the spec",
                    "state": "ready",
                    "author": "You",
                    "links": [{"label": "Notes", "kind": "file", "target": "/tmp/fictional-notes.txt"}],
                },
            )
        )
        cases = [
            {"label": "XSS", "kind": "web", "target": "javascript:alert(1)"},
            {"label": "Data", "kind": "web", "target": "data:text/html,hi"},
            {"label": "File as web", "kind": "web", "target": "file:///etc/passwd"},
            {"label": "Shell", "kind": "file", "target": "/tmp/notes.txt; rm -rf /"},
            {"label": "Relative", "kind": "folder", "target": "relative/path"},
        ]
        for link in cases:
            with self.subTest(target=link["target"]):
                proc = run_store(
                    self.data_dir,
                    "publish",
                    {
                        "activity_id": activity["id"],
                        "expected_revision": 1,
                        "summary": "Unsafe",
                        "next_step": "Should fail",
                        "state": "ready",
                        "author": "You",
                        "links": [link],
                    },
                )
                self.assertNotEqual(proc.returncode, 0, proc.stdout)
                err = decode(proc)
                self.assertFalse(err.get("ok"))
                self.assertEqual(err["error"], "validation")
        current = decode(run_store(self.data_dir, "get", {}))["current"]
        self.assertEqual(current["id"], good["current"]["id"])
        self.assertEqual(current["links"][0]["target"], "/tmp/fictional-notes.txt")

    def test_permission_error_is_clear_and_not_success(self) -> None:
        activity = decode(run_store(self.data_dir, "ensure-activity", {"name": "Study session"}))["activity"]
        decode(
            run_store(
                self.data_dir,
                "publish",
                {
                    "activity_id": activity["id"],
                    "expected_revision": 0,
                    "summary": "Saved",
                    "next_step": "Continue",
                    "state": "ready",
                    "author": "You",
                },
            )
        )
        db = self.data_dir / "breadcrumb.sqlite"
        os.chmod(db, 0o000)
        try:
            proc = run_store(
                self.data_dir,
                "publish",
                {
                    "activity_id": activity["id"],
                    "expected_revision": 1,
                    "summary": "Should fail",
                    "next_step": "No",
                    "state": "ready",
                    "author": "You",
                },
            )
        finally:
            os.chmod(db, 0o600)
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertFalse(err.get("ok"))
        self.assertEqual(err["error"], "permission")
        current = decode(run_store(self.data_dir, "get", {}))["current"]
        self.assertEqual(current["summary"], "Saved")

    def test_set_view_persists_compact_or_expanded(self) -> None:
        decode(run_store(self.data_dir, "ensure-activity", {"name": "Study session"}))
        self.assertEqual(decode(run_store(self.data_dir, "get", {}))["view"], "compact")
        proc = run_store(self.data_dir, "set-view", {"view": "expanded"})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["view"], "expanded")
        self.assertEqual(decode(run_store(self.data_dir, "get", {}))["view"], "expanded")
        bad = run_store(self.data_dir, "set-view", {"view": "sidebar"})
        self.assertNotEqual(bad.returncode, 0)
        self.assertEqual(decode(bad)["error"], "validation")
        self.assertEqual(decode(run_store(self.data_dir, "get", {}))["view"], "expanded")
        decode(run_store(self.data_dir, "set-view", {"view": "compact"}))
        self.assertEqual(decode(run_store(self.data_dir, "get", {}))["view"], "compact")

    def test_history_is_append_only_and_current_is_latest_revision(self) -> None:
        activity = decode(run_store(self.data_dir, "ensure-activity", {"name": "Study session"}))["activity"]
        first = decode(
            run_store(
                self.data_dir,
                "publish",
                {
                    "activity_id": activity["id"],
                    "expected_revision": 0,
                    "summary": "First",
                    "next_step": "A",
                    "state": "ready",
                    "author": "You",
                },
            )
        )
        second = decode(
            run_store(
                self.data_dir,
                "publish",
                {
                    "activity_id": activity["id"],
                    "expected_revision": 1,
                    "summary": "Second",
                    "next_step": "B",
                    "state": "in_progress",
                    "author": "You",
                },
            )
        )
        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        rows = conn.execute(
            "SELECT revision, summary FROM checkpoints WHERE activity_id = ? ORDER BY revision",
            (activity["id"],),
        ).fetchall()
        conn.close()
        self.assertEqual(rows, [(1, "First"), (2, "Second")])
        current = decode(run_store(self.data_dir, "get", {}))["current"]
        self.assertEqual(current["id"], second["current"]["id"])
        self.assertEqual(current["revision"], 2)
        self.assertNotEqual(first["current"]["id"], second["current"]["id"])

    def test_cli_accepts_argv_json_without_shell(self) -> None:
        activity = decode(run_store(self.data_dir, "ensure-activity", {"name": "Study session"}))["activity"]
        proc = run_store(
            self.data_dir,
            "publish",
            {
                "activity_id": activity["id"],
                "expected_revision": 0,
                "summary": "Via argv",
                "next_step": "Confirm",
                "state": "ready",
                "author": "You",
            },
            argv_json=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertEqual(body["current"]["summary"], "Via argv")

    def test_html_is_stored_as_plain_text(self) -> None:
        activity = decode(run_store(self.data_dir, "ensure-activity", {"name": "Study session"}))["activity"]
        payload = {
            "activity_id": activity["id"],
            "expected_revision": 0,
            "summary": "<script>alert(1)</script>",
            "next_step": "Treat as text",
            "context": "<b>not markup</b>",
            "state": "ready",
            "author": "You",
        }
        body = decode(run_store(self.data_dir, "publish", payload))
        self.assertEqual(body["current"]["summary"], "<script>alert(1)</script>")
        self.assertEqual(body["current"]["context"], "<b>not markup</b>")

    def test_schema_mismatch_is_a_clear_error(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        db = self.data_dir / "breadcrumb.sqlite"
        conn = sqlite3.connect(db)
        conn.execute("CREATE TABLE schema_meta (version INTEGER NOT NULL)")
        conn.execute("INSERT INTO schema_meta(version) VALUES (99)")
        conn.commit()
        conn.close()
        os.chmod(db, 0o600)
        proc = run_store(self.data_dir, "get", {})
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertFalse(err.get("ok"))
        self.assertEqual(err["error"], "schema")

    def test_validate_link_returns_open_argv_for_safe_targets(self) -> None:
        good = run_store(
            self.data_dir,
            "validate-link",
            {"kind": "web", "target": "https://example.com/notes"},
        )
        self.assertEqual(good.returncode, 0, good.stderr)
        body = decode(good)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["open_argv"], ["xdg-open", "--", "https://example.com/notes"])
        bad = run_store(self.data_dir, "validate-link", {"kind": "web", "target": "javascript:alert(1)"})
        self.assertNotEqual(bad.returncode, 0)
        self.assertEqual(decode(bad)["error"], "validation")

    def test_validate_link_reports_missing_file_without_shell(self) -> None:
        missing = run_store(
            self.data_dir,
            "validate-link",
            {"kind": "file", "target": "/tmp/breadcrumb-missing-lantern-map.txt"},
        )
        self.assertNotEqual(missing.returncode, 0)
        err = decode(missing)
        self.assertFalse(err.get("ok"))
        self.assertEqual(err["error"], "not_found")
        self.assertIn("missing", err["message"].lower())
        self.assertNotIn("open_argv", err)

        existing = Path(self.data_dir) / "lantern-notes.txt"
        existing.write_text("fictional", encoding="utf-8")
        good = run_store(
            self.data_dir,
            "validate-link",
            {"kind": "file", "target": str(existing)},
        )
        self.assertEqual(good.returncode, 0, good.stderr)
        body = decode(good)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["open_argv"], ["xdg-open", "--", str(existing)])

        folder = Path(self.data_dir) / "maps"
        folder.mkdir()
        folder_ok = run_store(
            self.data_dir,
            "validate-link",
            {"kind": "folder", "target": str(folder)},
        )
        self.assertEqual(folder_ok.returncode, 0, folder_ok.stderr)
        self.assertEqual(decode(folder_ok)["open_argv"][2], str(folder))

        as_file = run_store(
            self.data_dir,
            "validate-link",
            {"kind": "file", "target": str(folder)},
        )
        self.assertNotEqual(as_file.returncode, 0)
        self.assertEqual(decode(as_file)["error"], "validation")

        shellish = run_store(
            self.data_dir,
            "validate-link",
            {"kind": "file", "target": "/tmp/notes;rm -rf /"},
        )
        self.assertNotEqual(shellish.returncode, 0)
        self.assertEqual(decode(shellish)["error"], "validation")


if __name__ == "__main__":
    unittest.main()
