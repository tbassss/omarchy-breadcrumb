#!/usr/bin/env python3
"""Behavioral tests for named activities and checkpoint history (issue #4)."""

from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_store import STORE, decode, run_store


class TestActivities(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="breadcrumb-act-")
        self.data_dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_create_activity_mints_distinct_stable_ids(self) -> None:
        first = run_store(self.data_dir, "create-activity", {"name": "Study"})
        self.assertEqual(first.returncode, 0, first.stderr)
        first_body = decode(first)
        self.assertTrue(first_body.get("ok"), first_body)
        study = first_body["activity"]
        self.assertEqual(study["name"], "Study")
        self.assertRegex(
            study["id"],
            r"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
        )
        self.assertTrue(study["created_at"].endswith("Z"))
        self.assertIsNone(study.get("archived_at"))

        second = run_store(self.data_dir, "create-activity", {"name": "App Project"})
        self.assertEqual(second.returncode, 0, second.stderr)
        app = decode(second)["activity"]
        self.assertEqual(app["name"], "App Project")
        self.assertNotEqual(app["id"], study["id"])

        listed = decode(run_store(self.data_dir, "list-activities", {}))
        self.assertTrue(listed.get("ok"), listed)
        ids = [row["id"] for row in listed["activities"]]
        self.assertEqual(ids, [study["id"], app["id"]])
        self.assertEqual(listed["selected_activity_id"], app["id"])

    def _publish(self, activity_id: str, expected: int, summary: str, next_step: str) -> dict:
        proc = run_store(
            self.data_dir,
            "publish",
            {
                "activity_id": activity_id,
                "expected_revision": expected,
                "summary": summary,
                "next_step": next_step,
                "state": "in_progress",
                "author": "You",
            },
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertTrue(body.get("ok"), body)
        return body

    def test_activity_histories_stay_isolated_across_restart(self) -> None:
        study = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        app = decode(run_store(self.data_dir, "create-activity", {"name": "App Project"}))["activity"]
        self._publish(study["id"], 0, "Finished the routing lesson", "Work the subnetting set")
        self._publish(app["id"], 0, "Screen is ready for a hands-on check", "Walk the complete flow")
        self._publish(study["id"], 1, "Practice set is underway", "Recheck the last two answers")

        study_get = decode(run_store(self.data_dir, "get", {"activity_id": study["id"]}))
        app_get = decode(run_store(self.data_dir, "get", {"activity_id": app["id"]}))
        self.assertEqual(study_get["activity"]["id"], study["id"])
        self.assertEqual(study_get["current"]["summary"], "Practice set is underway")
        self.assertEqual(study_get["revision"], 2)
        self.assertEqual(app_get["activity"]["id"], app["id"])
        self.assertEqual(app_get["current"]["summary"], "Screen is ready for a hands-on check")
        self.assertEqual(app_get["revision"], 1)

        restarted = decode(run_store(self.data_dir, "get", {"activity_id": study["id"]}))
        self.assertEqual(restarted["current"]["summary"], "Practice set is underway")
        self.assertEqual(restarted["revision"], 2)
        after_study = decode(run_store(self.data_dir, "get", {}))
        self.assertEqual(after_study["activity"]["id"], study["id"])
        self.assertEqual(after_study["current"]["summary"], "Practice set is underway")
        other = decode(run_store(self.data_dir, "get", {"activity_id": app["id"]}))
        self.assertEqual(other["current"]["summary"], "Screen is ready for a hands-on check")
        defaulted = decode(run_store(self.data_dir, "get", {}))
        self.assertEqual(defaulted["activity"]["id"], app["id"])
        self.assertEqual(defaulted["current"]["summary"], "Screen is ready for a hands-on check")

    def test_rename_keeps_stable_id_and_history(self) -> None:
        study = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        published = self._publish(study["id"], 0, "Finished the routing lesson", "Work the subnetting set")
        renamed = run_store(
            self.data_dir,
            "rename-activity",
            {"activity_id": study["id"], "name": "WGU Course Notes"},
        )
        self.assertEqual(renamed.returncode, 0, renamed.stderr)
        body = decode(renamed)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["activity"]["id"], study["id"])
        self.assertEqual(body["activity"]["name"], "WGU Course Notes")
        self.assertEqual(body["activity"]["created_at"], study["created_at"])

        listed = decode(run_store(self.data_dir, "list-activities", {}))
        self.assertEqual(listed["activities"][0]["id"], study["id"])
        self.assertEqual(listed["activities"][0]["name"], "WGU Course Notes")
        got = decode(run_store(self.data_dir, "get", {"activity_id": study["id"]}))
        self.assertEqual(got["activity"]["name"], "WGU Course Notes")
        self.assertEqual(got["current"]["id"], published["current"]["id"])
        self.assertEqual(got["current"]["summary"], "Finished the routing lesson")
        self.assertEqual(got["revision"], 1)

        blank = run_store(self.data_dir, "rename-activity", {"activity_id": study["id"], "name": "  "})
        self.assertNotEqual(blank.returncode, 0)
        self.assertEqual(decode(blank)["error"], "validation")
        still = decode(run_store(self.data_dir, "get", {"activity_id": study["id"]}))
        self.assertEqual(still["activity"]["name"], "WGU Course Notes")
        self.assertEqual(still["current"]["id"], published["current"]["id"])

    def test_archive_is_not_deletion_and_archived_remain_accessible(self) -> None:
        study = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        personal = decode(run_store(self.data_dir, "create-activity", {"name": "Personal"}))["activity"]
        self._publish(study["id"], 0, "Finished the routing lesson", "Work the subnetting set")
        self._publish(personal["id"], 0, "Weekend shortlist is ready", "Compare the two routes")

        archived = run_store(self.data_dir, "archive-activity", {"activity_id": personal["id"]})
        self.assertEqual(archived.returncode, 0, archived.stderr)
        body = decode(archived)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["activity"]["id"], personal["id"])
        self.assertEqual(body["activity"]["name"], "Personal")
        self.assertIsNotNone(body["activity"]["archived_at"])
        self.assertTrue(body["activity"]["archived_at"].endswith("Z"))

        active = decode(run_store(self.data_dir, "list-activities", {}))
        self.assertEqual([row["id"] for row in active["activities"]], [study["id"]])
        with_archived = decode(run_store(self.data_dir, "list-activities", {"include_archived": True}))
        self.assertEqual([row["id"] for row in with_archived["activities"]], [study["id"], personal["id"]])
        self.assertIsNotNone(with_archived["activities"][1]["archived_at"])

        got = decode(run_store(self.data_dir, "get", {"activity_id": personal["id"]}))
        self.assertEqual(got["activity"]["id"], personal["id"])
        self.assertIsNotNone(got["activity"]["archived_at"])
        self.assertEqual(got["current"]["summary"], "Weekend shortlist is ready")
        self.assertEqual(got["revision"], 1)

        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        rows = conn.execute(
            "SELECT revision, summary FROM checkpoints WHERE activity_id = ? ORDER BY revision",
            (personal["id"],),
        ).fetchall()
        conn.close()
        self.assertEqual(rows, [(1, "Weekend shortlist is ready")])

        empty_archived = decode(run_store(self.data_dir, "list-activities", {}))
        self.assertEqual(len(empty_archived["activities"]), 1)
        again = run_store(self.data_dir, "archive-activity", {"activity_id": personal["id"]})
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertEqual(decode(again)["activity"]["archived_at"], body["activity"]["archived_at"])

    def test_history_pages_are_dated_bounded_and_isolated(self) -> None:
        study = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        other = decode(run_store(self.data_dir, "create-activity", {"name": "App Project"}))["activity"]
        first = self._publish(study["id"], 0, "Finished the routing lesson", "Work the subnetting set")
        second = self._publish(study["id"], 1, "Practice set is underway", "Recheck the last two answers")
        third = self._publish(study["id"], 2, "Wrong answers are marked", "Retry the subnetting set")
        self._publish(other["id"], 0, "Screen is ready for a hands-on check", "Walk the complete flow")

        page = run_store(
            self.data_dir,
            "history",
            {"activity_id": study["id"], "limit": 2},
        )
        self.assertEqual(page.returncode, 0, page.stderr)
        body = decode(page)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual([row["revision"] for row in body["entries"]], [3, 2])
        self.assertEqual(body["entries"][0]["id"], third["current"]["id"])
        self.assertEqual(body["entries"][0]["summary"], "Wrong answers are marked")
        self.assertTrue(body["entries"][0]["saved_at"].endswith("Z"))
        self.assertTrue(body["has_more"])
        self.assertEqual(body["next_before_revision"], 2)

        older = decode(
            run_store(
                self.data_dir,
                "history",
                {"activity_id": study["id"], "limit": 2, "before_revision": body["next_before_revision"]},
            )
        )
        self.assertEqual([row["revision"] for row in older["entries"]], [1])
        self.assertEqual(older["entries"][0]["id"], first["current"]["id"])
        self.assertFalse(older["has_more"])
        self.assertIsNone(older["next_before_revision"])

        other_hist = decode(run_store(self.data_dir, "history", {"activity_id": other["id"], "limit": 20}))
        self.assertEqual([row["summary"] for row in other_hist["entries"]], ["Screen is ready for a hands-on check"])
        self.assertFalse(other_hist["has_more"])

        too_big = run_store(self.data_dir, "history", {"activity_id": study["id"], "limit": 500})
        self.assertNotEqual(too_big.returncode, 0)
        self.assertEqual(decode(too_big)["error"], "validation")

        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        count = conn.execute("SELECT COUNT(*) FROM checkpoints WHERE activity_id = ?", (study["id"],)).fetchone()[0]
        conn.close()
        self.assertEqual(count, 3)

    def test_restore_appends_new_revision_and_never_rewrites_history(self) -> None:
        study = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        first = self._publish(study["id"], 0, "Finished the routing lesson", "Work the subnetting set")
        second = self._publish(study["id"], 1, "Practice set is underway", "Recheck the last two answers")
        first_id = first["current"]["id"]
        second_id = second["current"]["id"]

        restored = run_store(
            self.data_dir,
            "restore",
            {
                "activity_id": study["id"],
                "checkpoint_id": first_id,
                "expected_revision": 2,
            },
        )
        self.assertEqual(restored.returncode, 0, restored.stderr)
        body = decode(restored)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["revision"], 3)
        self.assertEqual(body["current"]["summary"], "Finished the routing lesson")
        self.assertEqual(body["current"]["next_step"], "Work the subnetting set")
        self.assertNotEqual(body["current"]["id"], first_id)
        self.assertNotEqual(body["current"]["id"], second_id)

        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        rows = conn.execute(
            "SELECT id, revision, summary FROM checkpoints WHERE activity_id = ? ORDER BY revision",
            (study["id"],),
        ).fetchall()
        conn.close()
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0], (first_id, 1, "Finished the routing lesson"))
        self.assertEqual(rows[1], (second_id, 2, "Practice set is underway"))
        self.assertEqual(rows[2][1], 3)
        self.assertEqual(rows[2][2], "Finished the routing lesson")
        self.assertNotEqual(rows[2][0], first_id)

        stale = run_store(
            self.data_dir,
            "restore",
            {
                "activity_id": study["id"],
                "checkpoint_id": second_id,
                "expected_revision": 2,
            },
        )
        self.assertEqual(stale.returncode, 4)
        self.assertEqual(decode(stale)["error"], "stale_revision")
        still = decode(run_store(self.data_dir, "get", {"activity_id": study["id"]}))
        self.assertEqual(still["revision"], 3)
        self.assertEqual(still["current"]["id"], body["current"]["id"])

        missing = run_store(
            self.data_dir,
            "restore",
            {
                "activity_id": study["id"],
                "checkpoint_id": "00000000-0000-0000-0000-000000000000",
                "expected_revision": 3,
            },
        )
        self.assertNotEqual(missing.returncode, 0)
        self.assertEqual(decode(missing)["error"], "validation")

    def test_empty_and_archived_lists_and_long_names_are_usable(self) -> None:
        empty = decode(run_store(self.data_dir, "list-activities", {"include_archived": True}))
        self.assertTrue(empty.get("ok"), empty)
        self.assertEqual(empty["activities"], [])
        self.assertIsNone(empty["selected_activity_id"])

        long_name = "A" * 200
        created = decode(run_store(self.data_dir, "create-activity", {"name": long_name}))
        self.assertTrue(created.get("ok"), created)
        self.assertEqual(created["activity"]["name"], long_name)
        too_long = run_store(self.data_dir, "create-activity", {"name": long_name + "Z"})
        self.assertNotEqual(too_long.returncode, 0)
        self.assertEqual(decode(too_long)["error"], "validation")

        only = decode(run_store(self.data_dir, "archive-activity", {"activity_id": created["activity"]["id"]}))
        self.assertIsNotNone(only["activity"]["archived_at"])
        active = decode(run_store(self.data_dir, "list-activities", {}))
        self.assertEqual(active["activities"], [])
        archived = decode(run_store(self.data_dir, "list-activities", {"include_archived": True}))
        self.assertEqual(len(archived["activities"]), 1)
        self.assertEqual(archived["activities"][0]["name"], long_name)
        got = decode(run_store(self.data_dir, "get", {"activity_id": created["activity"]["id"]}))
        self.assertEqual(got["activity"]["name"], long_name)

    def test_existing_v1_database_gains_archived_at_without_losing_rows(self) -> None:
        db = self.data_dir / "breadcrumb.sqlite"
        self.data_dir.mkdir(parents=True, exist_ok=True)
        os.chmod(self.data_dir, 0o700)
        conn = sqlite3.connect(db)
        conn.executescript(
            """
            CREATE TABLE schema_meta (version INTEGER NOT NULL);
            INSERT INTO schema_meta(version) VALUES (1);
            CREATE TABLE activities (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE checkpoints (
                id TEXT PRIMARY KEY,
                activity_id TEXT NOT NULL,
                revision INTEGER NOT NULL,
                summary TEXT NOT NULL,
                next_step TEXT,
                context TEXT,
                state TEXT NOT NULL,
                author TEXT NOT NULL,
                saved_at TEXT NOT NULL,
                UNIQUE(activity_id, revision)
            );
            CREATE TABLE checkpoint_links (
                checkpoint_id TEXT NOT NULL,
                position INTEGER NOT NULL,
                label TEXT NOT NULL,
                kind TEXT NOT NULL,
                target TEXT NOT NULL
            );
            CREATE TABLE prefs (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            INSERT INTO activities(id, name, created_at)
            VALUES ('11111111-1111-4111-8111-111111111111', 'Study', '2026-09-09T12:00:00Z');
            INSERT INTO checkpoints(
                id, activity_id, revision, summary, next_step, context, state, author, saved_at
            ) VALUES (
                '22222222-2222-4222-8222-222222222222',
                '11111111-1111-4111-8111-111111111111',
                1,
                'Finished the routing lesson',
                'Work the subnetting set',
                '',
                'in_progress',
                'You',
                '2026-09-09T12:01:00Z'
            );
            """
        )
        conn.commit()
        conn.close()
        os.chmod(db, 0o600)

        got = decode(run_store(self.data_dir, "get", {"activity_id": "11111111-1111-4111-8111-111111111111"}))
        self.assertTrue(got.get("ok"), got)
        self.assertEqual(got["activity"]["name"], "Study")
        self.assertIsNone(got["activity"]["archived_at"])
        self.assertEqual(got["current"]["summary"], "Finished the routing lesson")
        archived = decode(
            run_store(self.data_dir, "archive-activity", {"activity_id": "11111111-1111-4111-8111-111111111111"})
        )
        self.assertIsNotNone(archived["activity"]["archived_at"])
        listed = decode(run_store(self.data_dir, "list-activities", {"include_archived": True}))
        self.assertEqual(listed["activities"][0]["id"], "11111111-1111-4111-8111-111111111111")

    def test_concurrent_publish_isolates_activities_and_cas_restore(self) -> None:
        study = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        app = decode(run_store(self.data_dir, "create-activity", {"name": "App Project"}))["activity"]
        first = self._publish(study["id"], 0, "Finished the routing lesson", "Work the subnetting set")

        def start(command: str, payload: dict) -> subprocess.Popen[str]:
            env = os.environ.copy()
            env["BREADCRUMB_DATA_DIR"] = str(self.data_dir)
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            return subprocess.Popen(
                [sys.executable, str(STORE), command, json.dumps(payload)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
            )

        study_payload = {
            "activity_id": study["id"],
            "expected_revision": 1,
            "summary": "Practice set is underway",
            "next_step": "Recheck the last two answers",
            "state": "in_progress",
            "author": "You",
        }
        app_payload = {
            "activity_id": app["id"],
            "expected_revision": 0,
            "summary": "Screen is ready for a hands-on check",
            "next_step": "Walk the complete flow",
            "state": "in_progress",
            "author": "You",
        }
        left = start("publish", study_payload)
        right = start("publish", app_payload)
        left_out, left_err = left.communicate(timeout=15)
        right_out, right_err = right.communicate(timeout=15)
        self.assertEqual(left.returncode, 0, left_err)
        self.assertEqual(right.returncode, 0, right_err)
        self.assertEqual(json.loads(left_out)["revision"], 2)
        self.assertEqual(json.loads(right_out)["revision"], 1)

        restore_payload = {
            "activity_id": study["id"],
            "checkpoint_id": first["current"]["id"],
            "expected_revision": 2,
        }
        publish_payload = {
            "activity_id": study["id"],
            "expected_revision": 2,
            "summary": "Wrong answers are marked",
            "next_step": "Retry the subnetting set",
            "state": "in_progress",
            "author": "You",
        }
        first_proc = start("restore", restore_payload)
        second_proc = start("publish", publish_payload)
        first_out, first_err = first_proc.communicate(timeout=15)
        second_out, second_err = second_proc.communicate(timeout=15)
        codes = sorted([first_proc.returncode, second_proc.returncode])
        self.assertEqual(codes, [0, 4], f"{first_out!r} {first_err!r} {second_out!r} {second_err!r}")
        winner = json.loads(first_out if first_proc.returncode == 0 else second_out)
        self.assertEqual(winner["revision"], 3)
        got = decode(run_store(self.data_dir, "get", {"activity_id": study["id"]}))
        self.assertEqual(got["revision"], 3)
        hist = decode(run_store(self.data_dir, "history", {"activity_id": study["id"], "limit": 20}))
        self.assertEqual(len(hist["entries"]), 3)
        ids = [row["id"] for row in hist["entries"]]
        self.assertEqual(len(set(ids)), 3)


if __name__ == "__main__":
    unittest.main()
