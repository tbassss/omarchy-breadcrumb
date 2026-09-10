#!/usr/bin/env python3
"""Behavioral tests for the public Breadcrumb command (issue #6)."""

from __future__ import annotations

import json
import os
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

from test_store import decode, run_store

ROOT = Path(__file__).resolve().parents[1]
COMMAND = ROOT / "bin" / "breadcrumb"

STDIN_LIMIT = 65536


def run_command(
    data_dir: Path,
    argv: list[str],
    payload: dict | str | bytes | None = None,
    *,
    extra_env: dict | None = None,
    raw_stdin: bytes | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["BREADCRUMB_DATA_DIR"] = str(data_dir)
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    if extra_env:
        env.update(extra_env)
    if raw_stdin is not None:
        stdin_bytes = raw_stdin
        text = False
    elif isinstance(payload, bytes):
        stdin_bytes = payload
        text = False
    elif payload is None:
        stdin_bytes = None
        text = True
    elif isinstance(payload, str):
        stdin_bytes = payload
        text = True
    else:
        stdin_bytes = json.dumps(payload)
        text = True
    return subprocess.run(
        [sys.executable, str(COMMAND), *argv],
        input=stdin_bytes,
        capture_output=True,
        text=text,
        env=env,
        timeout=20,
    )


def decode_proc(proc: subprocess.CompletedProcess) -> dict:
    stdout = proc.stdout if isinstance(proc.stdout, str) else (proc.stdout or b"").decode("utf-8", "replace")
    if not stdout.strip():
        return {"_empty": True, "stderr": proc.stderr, "returncode": proc.returncode}
    return json.loads(stdout)


class TestPublicCommand(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="breadcrumb-cmd-")
        self.data_dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _create(self, name: str = "Study session") -> dict:
        return decode(run_store(self.data_dir, "create-activity", {"name": name}))["activity"]

    def _publish_store(self, activity_id: str, expected: int, summary: str, **extra) -> dict:
        payload = {
            "activity_id": activity_id,
            "expected_revision": expected,
            "summary": summary,
            "next_step": extra.get("next_step", "Keep going"),
            "context": extra.get("context", "Fictional notes."),
            "state": extra.get("state", "in_progress"),
            "author": extra.get("author", "You"),
        }
        if "links" in extra:
            payload["links"] = extra["links"]
        body = decode(run_store(self.data_dir, "publish", payload))
        self.assertTrue(body.get("ok"), body)
        return body

    def test_list_missing_store_is_empty_and_does_not_create(self) -> None:
        proc = run_command(self.data_dir, ["list"])
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode_proc(proc)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["v"], 1)
        self.assertEqual(body["op"], "list")
        self.assertEqual(body["activities"], [])
        self.assertFalse((self.data_dir / "breadcrumb.sqlite").exists())
        self.assertEqual(list(self.data_dir.iterdir()), [])

    def test_read_missing_store_does_not_create(self) -> None:
        proc = run_command(
            self.data_dir,
            ["read"],
            {"v": 1, "op": "read", "activity_id": "11111111-1111-4111-8111-111111111111"},
        )
        self.assertNotEqual(proc.returncode, 0)
        body = decode_proc(proc)
        self.assertFalse(body.get("ok"))
        self.assertEqual(body["error"], "validation")
        self.assertFalse((self.data_dir / "breadcrumb.sqlite").exists())

    def test_list_and_read_stable_ids_without_selecting(self) -> None:
        study = self._create("Study session")
        app = self._create("App Project")
        self._publish_store(study["id"], 0, "Finished the routing lesson")
        listed = decode_proc(run_command(self.data_dir, ["list"], {"v": 1, "op": "list"}))
        self.assertTrue(listed.get("ok"), listed)
        ids = [item["id"] for item in listed["activities"]]
        self.assertEqual(ids, [study["id"], app["id"]])
        self.assertEqual(listed["activities"][0]["revision"], 1)
        self.assertEqual(listed["activities"][0]["summary"], "Finished the routing lesson")
        self.assertEqual(listed["activities"][1]["revision"], 0)
        self.assertIsNone(listed["activities"][1]["summary"])

        selected_before = decode(run_store(self.data_dir, "get", {}))["activity"]["id"]
        self.assertEqual(selected_before, app["id"])
        read = decode_proc(
            run_command(self.data_dir, ["read"], {"v": 1, "op": "read", "activity_id": study["id"]})
        )
        self.assertTrue(read.get("ok"), read)
        self.assertEqual(read["activity"]["id"], study["id"])
        self.assertEqual(read["revision"], 1)
        self.assertEqual(read["current"]["summary"], "Finished the routing lesson")
        self.assertFalse(read["has_live_draft"])
        selected_after = decode(run_store(self.data_dir, "get", {}))["activity"]["id"]
        self.assertEqual(selected_after, app["id"])

    def test_read_unknown_activity_does_not_create(self) -> None:
        self._create("Study session")
        before = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        count = before.execute("SELECT COUNT(*) FROM activities").fetchone()[0]
        before.close()
        proc = run_command(
            self.data_dir,
            ["read"],
            {"v": 1, "op": "read", "activity_id": "22222222-2222-4222-8222-222222222222"},
        )
        self.assertNotEqual(proc.returncode, 0)
        err = decode_proc(proc)
        self.assertEqual(err["error"], "validation")
        after = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        self.assertEqual(after.execute("SELECT COUNT(*) FROM activities").fetchone()[0], count)
        after.close()

    def test_publish_requires_expected_revision_and_preserves_draft(self) -> None:
        activity = self._create()
        self._publish_store(activity["id"], 0, "First checkpoint")
        draft = decode(
            run_store(
                self.data_dir,
                "save-draft",
                {
                    "activity_id": activity["id"],
                    "expected_draft_revision": 0,
                    "base_revision": 1,
                    "summary": "Local draft against revision 1",
                    "next_step": "Keep this draft",
                    "context": "Fictional draft.",
                    "state": "in_progress",
                    "author": "You",
                },
            )
        )
        self.assertTrue(draft.get("ok"), draft)
        missing = run_command(
            self.data_dir,
            ["publish"],
            {
                "v": 1,
                "op": "publish",
                "activity_id": activity["id"],
                "summary": "Should not land",
                "next_step": "Missing expected revision",
                "state": "in_progress",
                "author": "Agent",
            },
        )
        self.assertNotEqual(missing.returncode, 0)
        self.assertEqual(decode_proc(missing)["error"], "validation")

        published = decode_proc(
            run_command(
                self.data_dir,
                ["publish"],
                {
                    "v": 1,
                    "op": "publish",
                    "activity_id": activity["id"],
                    "expected_revision": 1,
                    "summary": "Agent lantern v2",
                    "next_step": "Review the conflict",
                    "context": "Fictional agent note.",
                    "state": "in_progress",
                    "author": "Agent",
                },
            )
        )
        self.assertTrue(published.get("ok"), published)
        self.assertEqual(published["revision"], 2)
        self.assertEqual(published["current"]["summary"], "Agent lantern v2")
        self.assertTrue(published["has_live_draft"])
        read = decode_proc(run_command(self.data_dir, ["read"], {"v": 1, "op": "read", "activity_id": activity["id"]}))
        self.assertEqual(read["current"]["id"], published["checkpoint_id"])
        self.assertEqual(read["current"]["summary"], published["current"]["summary"])
        self.assertEqual(read["revision"], published["revision"])
        self.assertTrue(read["has_live_draft"])
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(got["draft"]["summary"], "Local draft against revision 1")
        self.assertEqual(got["draft"]["base_revision"], 1)
        self.assertEqual(got["revision"], 2)

    def test_malformed_and_oversized_input(self) -> None:
        activity = self._create()
        cases = [
            ("not-json", ["publish"], "{", 2, "invalid_request"),
            ("array", ["publish"], [1, 2], 2, "invalid_request"),
            ("wrong-v", ["list"], {"v": 2, "op": "list"}, 2, "invalid_request"),
            ("unknown-op", ["nope"], {"v": 1, "op": "nope"}, 2, "invalid_request"),
            (
                "consume-forbidden",
                ["publish"],
                {
                    "v": 1,
                    "op": "publish",
                    "activity_id": activity["id"],
                    "expected_revision": 0,
                    "summary": "Nope",
                    "next_step": "Nope",
                    "state": "ready",
                    "author": "Agent",
                    "consume_draft_revision": 1,
                },
                2,
                "invalid_request",
            ),
            (
                "string-revision",
                ["publish"],
                {
                    "v": 1,
                    "op": "publish",
                    "activity_id": activity["id"],
                    "expected_revision": "0",
                    "summary": "Nope",
                    "next_step": "Nope",
                    "state": "ready",
                    "author": "Agent",
                },
                3,
                "validation",
            ),
        ]
        for name, argv, payload, exit_status, error in cases:
            with self.subTest(name=name):
                proc = run_command(self.data_dir, argv, payload)
                self.assertEqual(proc.returncode, exit_status, proc.stdout)
                err = decode_proc(proc)
                self.assertFalse(err.get("ok"))
                self.assertEqual(err["error"], error)
                self.assertEqual(err["v"], 1)

        oversized = run_command(
            self.data_dir,
            ["publish"],
            raw_stdin=b"{" + b"a" * (STDIN_LIMIT + 1) + b"}",
        )
        self.assertEqual(oversized.returncode, 2)
        err = decode_proc(oversized)
        self.assertEqual(err["error"], "invalid_request")
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertIsNone(got["current"])
        self.assertEqual(got["revision"], 0)

    def test_same_revision_concurrent_writers_one_winner(self) -> None:
        activity = self._create()
        self._publish_store(activity["id"], 0, "First checkpoint")

        def start(summary: str) -> tuple[subprocess.Popen[str], str]:
            env = os.environ.copy()
            env["BREADCRUMB_DATA_DIR"] = str(self.data_dir)
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            payload = json.dumps(
                {
                    "v": 1,
                    "op": "publish",
                    "activity_id": activity["id"],
                    "expected_revision": 1,
                    "summary": summary,
                    "next_step": "Review the conflict",
                    "state": "in_progress",
                    "author": "Agent",
                }
            )
            proc = subprocess.Popen(
                [sys.executable, str(COMMAND), "publish"],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
            )
            return proc, payload

        left_proc, left_payload = start("Agent A")
        right_proc, right_payload = start("Agent B")
        def send(proc: subprocess.Popen[str], payload: str) -> tuple[str, str, int]:
            out, err = proc.communicate(payload, timeout=20)
            return out, err, proc.returncode

        left_out, left_err, left_code = send(left_proc, left_payload)
        right_out, right_err, right_code = send(right_proc, right_payload)
        bodies = [json.loads(left_out), json.loads(right_out)]
        codes = [left_code, right_code]
        winners = [body for body, code in zip(bodies, codes) if code == 0 and body.get("ok")]
        losers = [body for body, code in zip(bodies, codes) if code != 0]
        self.assertEqual(len(winners), 1, (left_out, right_out, left_err, right_err))
        self.assertEqual(len(losers), 1)
        self.assertEqual(losers[0]["error"], "stale_revision")
        self.assertEqual(winners[0]["revision"], 2)
        read = decode_proc(run_command(self.data_dir, ["read"], {"v": 1, "op": "read", "activity_id": activity["id"]}))
        self.assertEqual(read["revision"], 2)
        self.assertEqual(read["current"]["id"], winners[0]["checkpoint_id"])
        self.assertIn(read["current"]["summary"], {"Agent A", "Agent B"})
        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        count = conn.execute("SELECT COUNT(*) FROM checkpoints").fetchone()[0]
        conn.close()
        self.assertEqual(count, 2)

    def test_interrupted_publish_does_not_commit(self) -> None:
        activity = self._create()
        first = self._publish_store(activity["id"], 0, "First checkpoint")
        db = self.data_dir / "breadcrumb.sqlite"
        holder = sqlite3.connect(str(db), isolation_level=None)
        holder.execute("PRAGMA busy_timeout = 1")
        holder.execute("BEGIN IMMEDIATE")
        env = os.environ.copy()
        env["BREADCRUMB_DATA_DIR"] = str(self.data_dir)
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        payload = json.dumps(
            {
                "v": 1,
                "op": "publish",
                "activity_id": activity["id"],
                "expected_revision": 1,
                "summary": "Interrupted agent note",
                "next_step": "Should not land",
                "state": "in_progress",
                "author": "Agent",
            }
        )
        proc = subprocess.Popen(
            [sys.executable, str(COMMAND), "publish"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=env,
        )
        assert proc.stdin is not None
        proc.stdin.write(payload)
        proc.stdin.close()
        time.sleep(0.3)
        self.assertIsNone(proc.poll())
        proc.send_signal(signal.SIGKILL)
        proc.wait(timeout=5)
        self.assertNotEqual(proc.returncode, 0)
        stdout = ""
        if proc.stdout is not None:
            stdout = proc.stdout.read()
            proc.stdout.close()
        if proc.stderr is not None:
            proc.stderr.close()
        if stdout.strip():
            body = json.loads(stdout)
            self.assertFalse(body.get("ok", False))
        holder.execute("ROLLBACK")
        holder.close()
        read = decode_proc(run_command(self.data_dir, ["read"], {"v": 1, "op": "read", "activity_id": activity["id"]}))
        self.assertEqual(read["revision"], 1)
        self.assertEqual(read["current"]["id"], first["current"]["id"])
        self.assertEqual(read["current"]["summary"], "First checkpoint")
        conn = sqlite3.connect(db)
        summaries = [row[0] for row in conn.execute("SELECT summary FROM checkpoints")]
        conn.close()
        self.assertEqual(summaries, ["First checkpoint"])

    def test_public_cli_rejects_draft_ops(self) -> None:
        for op in ("save-draft", "discard-draft", "ensure-activity", "create-activity", "delete-archived-activity", "delete", "unarchive-activity", "unarchive", "archive-activity"):
            proc = run_command(self.data_dir, [op], {"v": 1, "op": op})
            self.assertEqual(proc.returncode, 2, proc.stdout)
            self.assertEqual(decode_proc(proc)["error"], "invalid_request")


if __name__ == "__main__":
    unittest.main()
