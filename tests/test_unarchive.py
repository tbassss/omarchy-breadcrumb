#!/usr/bin/env python3
"""Behavioral tests for unarchiving a stable activity.

Internal store command only. Fictional fixtures. Not history Restore.
Not permanent delete. Does not recreate a deleted activity.
"""

from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_delete_archived import counts
from test_store import STORE, decode, run_store


class TestUnarchiveActivity(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="breadcrumb-unarchive-")
        self.data_dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _create(self, name: str) -> dict:
        return decode(run_store(self.data_dir, "create-activity", {"name": name}))["activity"]

    def _publish(self, activity_id: str, expected: int, summary: str, *, links: list | None = None) -> dict:
        payload = {
            "activity_id": activity_id,
            "expected_revision": expected,
            "summary": summary,
            "next_step": "Continue the fictional notes",
            "context": "Fictional checkpoint only.",
            "state": "in_progress",
            "author": "You",
        }
        if links is not None:
            payload["links"] = links
        body = decode(run_store(self.data_dir, "publish", payload))
        self.assertTrue(body.get("ok"), body)
        return body

    def _draft(self, activity_id: str, expected: int, summary: str, *, base: int = 0, links: list | None = None) -> dict:
        payload = {
            "activity_id": activity_id,
            "expected_draft_revision": expected,
            "base_revision": base,
            "summary": summary,
            "next_step": "Keep the fictional draft",
            "context": "Fictional draft only.",
            "state": "in_progress",
            "author": "You",
        }
        if links is not None:
            payload["links"] = links
        body = decode(run_store(self.data_dir, "save-draft", payload))
        self.assertTrue(body.get("ok"), body)
        return body

    def _archive(self, activity_id: str) -> dict:
        body = decode(run_store(self.data_dir, "archive-activity", {"activity_id": activity_id}))
        self.assertTrue(body.get("ok"), body)
        return body["activity"]

    def _frozen(self, activity_id: str) -> dict:
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity_id, "include_archived": True}))
        self.assertTrue(got.get("ok"), got)
        activity = got["activity"]
        return {
            "activity_id": activity["id"],
            "expected_revision": int(got["revision"]),
            "expected_draft_revision": int(got.get("draft_generation") or 0),
            "expected_archived_at": activity["archived_at"],
            "expected_archive_generation": int(activity.get("archive_generation") or 0),
            "expected_name": activity["name"],
        }

    def _force_archived_at(self, activity_id: str, archived_at: str) -> None:
        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        try:
            conn.execute("UPDATE activities SET archived_at = ? WHERE id = ?", (archived_at, activity_id))
            conn.commit()
        finally:
            conn.close()

    def _start(self, command: str, payload: dict) -> subprocess.Popen[str]:
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

    def test_unarchive_returns_exact_activity_without_new_checkpoint(self) -> None:
        keep = self._create("Keep Lantern Notes")
        gone = self._create("Gone Trail Map")
        keep_pub = self._publish(keep["id"], 0, "Keep published lantern count")
        self._publish(gone["id"], 0, "Gone published trail notes")
        second = self._publish(
            gone["id"],
            1,
            "Second trail checkpoint",
            links=[{"label": "Spec", "kind": "web", "target": "https://example.com/trail"}],
        )
        draft = self._draft(gone["id"], 0, "Gone durable draft must survive unarchive", base=2)
        archived = self._archive(gone["id"])
        self.assertIsNotNone(archived["archived_at"])
        before = counts(self.data_dir, gone["id"])
        selected = decode(run_store(self.data_dir, "list-activities", {"include_archived": True}))
        self.assertEqual(selected["selected_activity_id"], gone["id"])

        proc = run_store(self.data_dir, "unarchive-activity", {"activity_id": gone["id"]})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["activity"]["id"], gone["id"])
        self.assertEqual(body["activity"]["name"], "Gone Trail Map")
        self.assertIsNone(body["activity"]["archived_at"])

        active = decode(run_store(self.data_dir, "list-activities", {}))
        self.assertEqual([row["id"] for row in active["activities"]], [keep["id"], gone["id"]])
        self.assertEqual(active["selected_activity_id"], gone["id"])
        self.assertTrue(all(row["archived_at"] is None for row in active["activities"]))

        got = decode(run_store(self.data_dir, "get", {"activity_id": gone["id"]}))
        self.assertEqual(got["activity"]["id"], gone["id"])
        self.assertIsNone(got["activity"]["archived_at"])
        self.assertEqual(got["revision"], 2)
        self.assertEqual(got["current"]["id"], second["current"]["id"])
        self.assertEqual(got["current"]["summary"], "Second trail checkpoint")
        self.assertEqual(got["current"]["links"][0]["target"], "https://example.com/trail")
        self.assertEqual(got["draft"]["summary"], "Gone durable draft must survive unarchive")
        self.assertEqual(got["draft"]["revision"], draft["draft"]["revision"])
        self.assertEqual([row["revision"] for row in got["history"]["entries"]], [2, 1])

        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        rows = conn.execute(
            "SELECT revision, summary FROM checkpoints WHERE activity_id = ? ORDER BY revision",
            (gone["id"],),
        ).fetchall()
        conn.close()
        self.assertEqual(rows, [(1, "Gone published trail notes"), (2, "Second trail checkpoint")])
        self.assertEqual(counts(self.data_dir, gone["id"]), before)
        self.assertEqual(counts(self.data_dir, keep["id"])["checkpoints"], 1)
        self.assertEqual(keep_pub["revision"], 1)

        again = run_store(self.data_dir, "unarchive-activity", {"activity_id": gone["id"]})
        self.assertEqual(again.returncode, 0, again.stderr)
        self.assertIsNone(decode(again)["activity"]["archived_at"])
        self.assertEqual(counts(self.data_dir, gone["id"]), before)

    def test_unarchive_unknown_and_deleted_cannot_resurrect(self) -> None:
        missing = run_store(
            self.data_dir,
            "unarchive-activity",
            {"activity_id": "11111111-1111-4111-8111-111111111111"},
        )
        self.assertNotEqual(missing.returncode, 0)
        self.assertEqual(decode(missing)["error"], "validation")

        gone = self._create("Gone Trail Map")
        self._publish(gone["id"], 0, "Gone published trail notes")
        self._archive(gone["id"])
        frozen = self._frozen(gone["id"])
        deleted = decode(run_store(self.data_dir, "delete-archived-activity", frozen))
        self.assertTrue(deleted.get("ok"), deleted)
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 0)

        resurrect = run_store(self.data_dir, "unarchive-activity", {"activity_id": gone["id"]})
        self.assertNotEqual(resurrect.returncode, 0)
        self.assertEqual(decode(resurrect)["error"], "validation")
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 0)
        listed = decode(run_store(self.data_dir, "list-activities", {"include_archived": True}))
        self.assertEqual(listed["activities"], [])

    def test_stale_delete_after_unarchive_rejects_without_mutating(self) -> None:
        keep = self._create("Keep Lantern Notes")
        gone = self._create("Gone Trail Map")
        self._publish(keep["id"], 0, "Keep published lantern count")
        self._publish(gone["id"], 0, "Gone published trail notes")
        self._draft(gone["id"], 0, "Keep this draft", base=1)
        self._archive(gone["id"])
        frozen = self._frozen(gone["id"])
        unarchived = decode(run_store(self.data_dir, "unarchive-activity", {"activity_id": gone["id"]}))
        self.assertTrue(unarchived.get("ok"), unarchived)
        self.assertIsNone(unarchived["activity"]["archived_at"])

        proc = run_store(self.data_dir, "delete-archived-activity", frozen)
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertEqual(err["error"], "validation")
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 1)
        got = decode(run_store(self.data_dir, "get", {"activity_id": gone["id"]}))
        self.assertIsNone(got["activity"]["archived_at"])
        self.assertEqual(got["current"]["summary"], "Gone published trail notes")
        self.assertEqual(got["draft"]["summary"], "Keep this draft")
        self.assertEqual(counts(self.data_dir, keep["id"])["activities"], 1)

    def test_unarchive_isolates_neighbor_and_failed_write_rolls_back(self) -> None:
        keep = self._create("Keep Lantern Notes")
        gone = self._create("Gone Trail Map")
        self._publish(keep["id"], 0, "Keep published lantern count")
        self._publish(gone["id"], 0, "Gone published trail notes")
        keep_archived = self._archive(keep["id"])
        self._archive(gone["id"])
        before_keep = counts(self.data_dir, keep["id"])

        body = decode(run_store(self.data_dir, "unarchive-activity", {"activity_id": gone["id"]}))
        self.assertTrue(body.get("ok"), body)
        self.assertIsNone(body["activity"]["archived_at"])
        keep_got = decode(run_store(self.data_dir, "get", {"activity_id": keep["id"], "include_archived": True}))
        self.assertEqual(keep_got["activity"]["archived_at"], keep_archived["archived_at"])
        self.assertEqual(counts(self.data_dir, keep["id"]), before_keep)

        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        conn.execute(
            """
            CREATE TRIGGER breadcrumb_fail_unarchive
            BEFORE UPDATE ON activities
            WHEN NEW.archived_at IS NULL AND OLD.archived_at IS NOT NULL
            BEGIN
                SELECT RAISE(ABORT, 'injected unarchive fault');
            END
            """
        )
        conn.commit()
        conn.close()
        before_gone = counts(self.data_dir, gone["id"])
        self._archive(gone["id"])
        still_archived = decode(run_store(self.data_dir, "get", {"activity_id": gone["id"], "include_archived": True}))
        self.assertIsNotNone(still_archived["activity"]["archived_at"])
        proc = run_store(self.data_dir, "unarchive-activity", {"activity_id": gone["id"]})
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertEqual(err["error"], "io")
        self.assertFalse(err.get("ok"))
        still = decode(run_store(self.data_dir, "get", {"activity_id": gone["id"], "include_archived": True}))
        self.assertIsNotNone(still["activity"]["archived_at"])
        self.assertEqual(still["current"]["summary"], "Gone published trail notes")
        self.assertEqual(counts(self.data_dir, gone["id"])["checkpoints"], before_gone["checkpoints"])

    def test_same_second_unarchive_rearchive_rejects_old_delete_bytes(self) -> None:
        gone = self._create("Gone Trail Map")
        self._publish(gone["id"], 0, "Gone published trail notes")
        self._draft(gone["id"], 0, "Keep this draft", base=1)
        archived = self._archive(gone["id"])
        frozen = self._frozen(gone["id"])
        first_at = archived["archived_at"]
        before = counts(self.data_dir, gone["id"])

        unarchived = decode(run_store(self.data_dir, "unarchive-activity", {"activity_id": gone["id"]}))
        self.assertTrue(unarchived.get("ok"), unarchived)
        rearchived = self._archive(gone["id"])
        self.assertIsNotNone(rearchived["archived_at"])
        self._force_archived_at(gone["id"], first_at)
        after_cycle = decode(run_store(self.data_dir, "get", {"activity_id": gone["id"], "include_archived": True}))
        self.assertEqual(after_cycle["activity"]["archived_at"], first_at)
        self.assertEqual(after_cycle["activity"]["archived_at"], frozen["expected_archived_at"])

        proc = run_store(self.data_dir, "delete-archived-activity", frozen)
        self.assertNotEqual(proc.returncode, 0, proc.stdout)
        err = decode(proc)
        self.assertEqual(err["error"], "stale_revision")
        self.assertIn("current_archive_generation", err)
        self.assertNotEqual(err["current_archive_generation"], frozen["expected_archive_generation"])
        self.assertEqual(counts(self.data_dir, gone["id"]), before)
        still = decode(run_store(self.data_dir, "get", {"activity_id": gone["id"], "include_archived": True}))
        self.assertEqual(still["current"]["summary"], "Gone published trail notes")
        self.assertEqual(still["draft"]["summary"], "Keep this draft")
        self.assertGreater(int(still["activity"]["archive_generation"]), int(frozen["expected_archive_generation"]))

    def test_wall_clock_rollback_does_not_reuse_delete_consent(self) -> None:
        gone = self._create("Gone Trail Map")
        self._publish(gone["id"], 0, "Gone published trail notes")
        archived = self._archive(gone["id"])
        frozen = self._frozen(gone["id"])
        decode(run_store(self.data_dir, "unarchive-activity", {"activity_id": gone["id"]}))
        self._archive(gone["id"])
        self._force_archived_at(gone["id"], "2020-01-01T00:00:00Z")
        proc = run_store(self.data_dir, "delete-archived-activity", frozen)
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertEqual(err["error"], "stale_revision")
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 1)

        self._force_archived_at(gone["id"], archived["archived_at"])
        replay = run_store(self.data_dir, "delete-archived-activity", frozen)
        self.assertNotEqual(replay.returncode, 0)
        replay_err = decode(replay)
        self.assertEqual(replay_err["error"], "stale_revision")
        self.assertIn("current_archive_generation", replay_err)
        self.assertNotEqual(replay_err["current_archive_generation"], frozen["expected_archive_generation"])
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 1)

    def test_repeated_same_time_cycles_reject_prior_consents_and_accept_current(self) -> None:
        gone = self._create("Gone Trail Map")
        self._publish(gone["id"], 0, "Gone published trail notes")
        first_at = ""
        frozen_payloads: list[dict] = []
        for _ in range(3):
            archived = self._archive(gone["id"])
            if not first_at:
                first_at = archived["archived_at"]
            else:
                self._force_archived_at(gone["id"], first_at)
            frozen_payloads.append(self._frozen(gone["id"]))
            decode(run_store(self.data_dir, "unarchive-activity", {"activity_id": gone["id"]}))
        archived = self._archive(gone["id"])
        self._force_archived_at(gone["id"], first_at)
        current = self._frozen(gone["id"])
        for old in frozen_payloads:
            proc = run_store(self.data_dir, "delete-archived-activity", old)
            self.assertNotEqual(proc.returncode, 0, old)
            self.assertEqual(decode(proc)["error"], "stale_revision")
            self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 1)
        accepted = decode(run_store(self.data_dir, "delete-archived-activity", current))
        self.assertTrue(accepted.get("ok"), accepted)
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 0)

    def test_second_instance_confirmation_deletes_after_first_instance_stale(self) -> None:
        gone = self._create("Gone Trail Map")
        keep = self._create("Keep Lantern Notes")
        self._publish(gone["id"], 0, "Gone published trail notes")
        self._publish(keep["id"], 0, "Keep published lantern count")
        archived = self._archive(gone["id"])
        first_at = archived["archived_at"]
        frozen_a = self._frozen(gone["id"])
        decode(run_store(self.data_dir, "unarchive-activity", {"activity_id": gone["id"]}))
        self._archive(gone["id"])
        self._force_archived_at(gone["id"], first_at)
        frozen_b = self._frozen(gone["id"])
        self.assertEqual(frozen_a["expected_archived_at"], frozen_b["expected_archived_at"])
        self.assertNotEqual(frozen_a["expected_archive_generation"], frozen_b["expected_archive_generation"])

        stale = run_store(self.data_dir, "delete-archived-activity", frozen_a)
        self.assertNotEqual(stale.returncode, 0)
        self.assertEqual(decode(stale)["error"], "stale_revision")
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 1)

        accepted = decode(run_store(self.data_dir, "delete-archived-activity", frozen_b))
        self.assertTrue(accepted.get("ok"), accepted)
        self.assertEqual(accepted["deleted_activity_id"], gone["id"])
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 0)
        self.assertEqual(counts(self.data_dir, keep["id"])["activities"], 1)

    def test_concurrent_archive_delete_unarchive_serial_outcomes(self) -> None:
        gone = self._create("Gone Trail Map")
        keep = self._create("Keep Lantern Notes")
        self._publish(gone["id"], 0, "Gone published trail notes")
        self._draft(gone["id"], 0, "Keep this draft", base=1)
        self._archive(gone["id"])
        frozen = self._frozen(gone["id"])

        deleter = self._start("delete-archived-activity", frozen)
        unarchiver = self._start("unarchive-activity", {"activity_id": gone["id"]})
        delete_out, delete_err = deleter.communicate(timeout=15)
        unarchive_out, unarchive_err = unarchiver.communicate(timeout=15)
        delete_body = json.loads(delete_out) if delete_out.strip() else {"_empty": True, "stderr": delete_err}
        unarchive_body = json.loads(unarchive_out) if unarchive_out.strip() else {"_empty": True, "stderr": unarchive_err}
        delete_ok = bool(delete_body.get("ok"))
        unarchive_ok = bool(unarchive_body.get("ok"))
        self.assertNotEqual(delete_ok and unarchive_ok, True)
        remaining = counts(self.data_dir, gone["id"])["activities"]
        if delete_ok:
            self.assertEqual(remaining, 0)
            self.assertEqual(unarchive_body.get("error"), "validation")
            resurrect = run_store(self.data_dir, "unarchive-activity", {"activity_id": gone["id"]})
            self.assertNotEqual(resurrect.returncode, 0)
            self.assertEqual(decode(resurrect)["error"], "validation")
        else:
            self.assertEqual(remaining, 1)
            self.assertTrue(unarchive_ok, unarchive_body)
            got = decode(run_store(self.data_dir, "get", {"activity_id": gone["id"]}))
            self.assertIsNone(got["activity"]["archived_at"])
            self.assertEqual(got["current"]["summary"], "Gone published trail notes")
            self.assertEqual(got["draft"]["summary"], "Keep this draft")
            stale = run_store(self.data_dir, "delete-archived-activity", frozen)
            self.assertNotEqual(stale.returncode, 0)
            self.assertEqual(decode(stale)["error"], "validation")
        self.assertEqual(counts(self.data_dir, keep["id"])["activities"], 1)

        active = self._create("Active Lantern")
        self._publish(active["id"], 0, "Active checkpoint")
        archiver = self._start("archive-activity", {"activity_id": active["id"]})
        active_delete = self._start(
            "delete-archived-activity",
            {
                "activity_id": active["id"],
                "expected_revision": 1,
                "expected_draft_revision": 0,
                "expected_archived_at": "2026-01-01T00:00:00Z",
                "expected_archive_generation": 1,
                "expected_name": "Active Lantern",
            },
        )
        archive_out, _ = archiver.communicate(timeout=15)
        active_delete_out, _ = active_delete.communicate(timeout=15)
        archive_body = json.loads(archive_out)
        active_delete_body = json.loads(active_delete_out)
        self.assertTrue(archive_body.get("ok"), archive_body)
        self.assertFalse(active_delete_body.get("ok"))
        self.assertIn(active_delete_body["error"], ("validation", "stale_revision"))
        still_active = decode(run_store(self.data_dir, "get", {"activity_id": active["id"], "include_archived": True}))
        self.assertIsNotNone(still_active["activity"]["archived_at"])
        self.assertEqual(still_active["current"]["summary"], "Active checkpoint")
        self.assertEqual(counts(self.data_dir, active["id"])["activities"], 1)


if __name__ == "__main__":
    unittest.main()
