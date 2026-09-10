#!/usr/bin/env python3
"""Behavioral tests for unarchiving a stable activity.

Internal store command only. Fictional fixtures. Not history Restore.
Not permanent delete. Does not recreate a deleted activity.
"""

from __future__ import annotations

import sqlite3
import tempfile
import unittest
from pathlib import Path

from test_delete_archived import counts
from test_store import decode, run_store


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
            "expected_name": activity["name"],
        }

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


if __name__ == "__main__":
    unittest.main()
