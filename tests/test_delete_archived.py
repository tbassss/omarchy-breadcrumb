#!/usr/bin/env python3
"""Behavioral tests for archived-activity permanent deletion.

Internal store command only. Fictional fixtures.
"""

from __future__ import annotations

import os
import sqlite3
import tempfile
import unittest
from pathlib import Path

from test_store import decode, run_store


def counts(data_dir: Path, activity_id: str) -> dict[str, int]:
    conn = sqlite3.connect(data_dir / "breadcrumb.sqlite")
    try:
        checkpoints = conn.execute(
            "SELECT COUNT(*) FROM checkpoints WHERE activity_id = ?",
            (activity_id,),
        ).fetchone()[0]
        links = conn.execute(
            """
            SELECT COUNT(*) FROM checkpoint_links
            WHERE checkpoint_id IN (SELECT id FROM checkpoints WHERE activity_id = ?)
            """,
            (activity_id,),
        ).fetchone()[0]
        drafts = conn.execute(
            "SELECT COUNT(*) FROM drafts WHERE activity_id = ?",
            (activity_id,),
        ).fetchone()[0]
        draft_links = conn.execute(
            "SELECT COUNT(*) FROM draft_links WHERE activity_id = ?",
            (activity_id,),
        ).fetchone()[0]
        activities = conn.execute(
            "SELECT COUNT(*) FROM activities WHERE id = ?",
            (activity_id,),
        ).fetchone()[0]
    finally:
        conn.close()
    return {
        "activities": activities,
        "checkpoints": checkpoints,
        "checkpoint_links": links,
        "drafts": drafts,
        "draft_links": draft_links,
    }


class TestDeleteArchivedActivity(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="breadcrumb-delete-")
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

    def test_delete_archived_removes_children_and_isolates_neighbor(self) -> None:
        keep = self._create("Keep Lantern Notes")
        gone = self._create("Gone Trail Map")
        self._publish(
            keep["id"],
            0,
            "Keep published v1",
            links=[{"label": "Keep site", "kind": "web", "target": "https://example.com/keep"}],
        )
        self._draft(
            keep["id"],
            0,
            "Keep draft",
            base=1,
            links=[{"label": "Keep draft link", "kind": "web", "target": "https://example.com/keep-draft"}],
        )
        self._publish(
            gone["id"],
            0,
            "Gone published v1",
            links=[{"label": "Gone site", "kind": "web", "target": "https://example.com/gone"}],
        )
        self._publish(gone["id"], 1, "Gone published v2")
        self._draft(
            gone["id"],
            0,
            "Gone draft",
            base=2,
            links=[{"label": "Gone draft link", "kind": "web", "target": "https://example.com/gone-draft"}],
        )
        archived = self._archive(gone["id"])
        self.assertIsNotNone(archived["archived_at"])

        keep_before = counts(self.data_dir, keep["id"])
        gone_before = counts(self.data_dir, gone["id"])
        self.assertEqual(gone_before["activities"], 1)
        self.assertEqual(gone_before["checkpoints"], 2)
        self.assertGreaterEqual(gone_before["checkpoint_links"], 1)
        self.assertEqual(gone_before["drafts"], 1)
        self.assertEqual(gone_before["draft_links"], 1)

        proc = run_store(self.data_dir, "delete-archived-activity", self._frozen(gone["id"]))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["deleted_activity_id"], gone["id"])
        self.assertEqual(body["selected_activity_id"], keep["id"])

        self.assertEqual(counts(self.data_dir, gone["id"]), {
            "activities": 0,
            "checkpoints": 0,
            "checkpoint_links": 0,
            "drafts": 0,
            "draft_links": 0,
        })
        self.assertEqual(counts(self.data_dir, keep["id"]), keep_before)

        listed = decode(run_store(self.data_dir, "list-activities", {"include_archived": True}))
        self.assertEqual([row["id"] for row in listed["activities"]], [keep["id"]])
        resurrect = run_store(
            self.data_dir,
            "save-draft",
            {
                "activity_id": gone["id"],
                "expected_draft_revision": 0,
                "base_revision": 0,
                "summary": "must not resurrect",
                "next_step": "no",
                "state": "ready",
                "author": "You",
            },
        )
        self.assertNotEqual(resurrect.returncode, 0)
        self.assertEqual(decode(resurrect)["error"], "validation")
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 0)

    def test_active_activity_cannot_be_deleted(self) -> None:
        study = self._create("Study Notes")
        self._publish(study["id"], 0, "Active checkpoint")
        frozen = {
            "activity_id": study["id"],
            "expected_revision": 1,
            "expected_draft_revision": 0,
            "expected_archived_at": "2026-01-01T00:00:00Z",
            "expected_archive_generation": 0,
            "expected_name": "Study Notes",
        }
        proc = run_store(self.data_dir, "delete-archived-activity", frozen)
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertEqual(err["error"], "validation")
        self.assertIn("archived", err["message"].lower())
        self.assertEqual(counts(self.data_dir, study["id"])["activities"], 1)
        self.assertEqual(counts(self.data_dir, study["id"])["checkpoints"], 1)

    def test_stale_confirmation_rejects_concurrent_publication_and_draft(self) -> None:
        gone = self._create("Stale Trail")
        self._publish(gone["id"], 0, "Published v1")
        archived = self._archive(gone["id"])
        frozen = {
            "activity_id": gone["id"],
            "expected_revision": 1,
            "expected_draft_revision": 0,
            "expected_archived_at": archived["archived_at"],
            "expected_archive_generation": int(archived.get("archive_generation") or 0),
            "expected_name": "Stale Trail",
        }
        self._publish(gone["id"], 1, "Published v2 after confirm")
        proc = run_store(self.data_dir, "delete-archived-activity", frozen)
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertEqual(err["error"], "stale_revision")
        self.assertEqual(err["current_revision"], 2)
        self.assertEqual(err["expected_revision"], 1)
        self.assertEqual(counts(self.data_dir, gone["id"])["checkpoints"], 2)

        frozen2 = self._frozen(gone["id"])
        self._draft(gone["id"], 0, "Draft after confirm", base=2)
        proc = run_store(self.data_dir, "delete-archived-activity", frozen2)
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertEqual(err["error"], "stale_revision")
        self.assertEqual(err["current_draft_revision"], 1)
        self.assertEqual(err["expected_draft_revision"], 0)
        self.assertEqual(counts(self.data_dir, gone["id"])["drafts"], 1)
        got = decode(run_store(self.data_dir, "get", {"activity_id": gone["id"], "include_archived": True}))
        self.assertEqual(got["draft"]["summary"], "Draft after confirm")

    def test_stale_archived_at_and_name_reject_without_delete(self) -> None:
        gone = self._create("Rename Me")
        archived = self._archive(gone["id"])
        frozen = {
            "activity_id": gone["id"],
            "expected_revision": 0,
            "expected_draft_revision": 0,
            "expected_archived_at": archived["archived_at"],
            "expected_archive_generation": int(archived.get("archive_generation") or 0),
            "expected_name": "Rename Me",
        }
        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        conn.execute("UPDATE activities SET archived_at = NULL WHERE id = ?", (gone["id"],))
        conn.commit()
        conn.close()
        proc = run_store(self.data_dir, "delete-archived-activity", frozen)
        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(decode(proc)["error"], "validation")
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 1)

        archived = self._archive(gone["id"])
        frozen = {
            "activity_id": gone["id"],
            "expected_revision": 0,
            "expected_draft_revision": 0,
            "expected_archived_at": "2020-01-01T00:00:00Z",
            "expected_archive_generation": int(archived.get("archive_generation") or 0),
            "expected_name": "Rename Me",
        }
        proc = run_store(self.data_dir, "delete-archived-activity", frozen)
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertEqual(err["error"], "stale_revision")
        self.assertEqual(err["current_archived_at"], archived["archived_at"])
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 1)

        decode(run_store(self.data_dir, "rename-activity", {"activity_id": gone["id"], "name": "Renamed Trail"}))
        frozen = {
            "activity_id": gone["id"],
            "expected_revision": 0,
            "expected_draft_revision": 0,
            "expected_archived_at": archived["archived_at"],
            "expected_archive_generation": int(archived.get("archive_generation") or 0),
            "expected_name": "Rename Me",
        }
        proc = run_store(self.data_dir, "delete-archived-activity", frozen)
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertEqual(err["error"], "stale_revision")
        self.assertEqual(err["current_name"], "Renamed Trail")
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 1)

    def test_last_archived_activity_clears_selection(self) -> None:
        only = self._create("Only Trail")
        self._publish(only["id"], 0, "Only checkpoint")
        self._archive(only["id"])
        proc = run_store(self.data_dir, "delete-archived-activity", self._frozen(only["id"]))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertTrue(body.get("ok"), body)
        self.assertEqual(body["deleted_activity_id"], only["id"])
        self.assertIsNone(body["selected_activity_id"])
        listed = decode(run_store(self.data_dir, "list-activities", {"include_archived": True}))
        self.assertEqual(listed["activities"], [])
        got = decode(run_store(self.data_dir, "get", {}))
        self.assertEqual(got["state"], "empty")
        self.assertIsNone(got["activity"])
        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        pref = conn.execute("SELECT value FROM prefs WHERE key = 'selected_activity_id'").fetchone()
        conn.close()
        self.assertIsNone(pref)

    def test_failed_delete_preserves_draft_and_history(self) -> None:
        gone = self._create("Faulty Trail")
        self._publish(gone["id"], 0, "Keep this checkpoint")
        self._draft(gone["id"], 0, "Keep this draft", base=1)
        self._archive(gone["id"])
        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        conn.execute(
            """
            CREATE TRIGGER breadcrumb_fail_delete
            BEFORE DELETE ON activities
            BEGIN
                SELECT RAISE(ABORT, 'injected delete fault');
            END
            """
        )
        conn.commit()
        conn.close()
        before = counts(self.data_dir, gone["id"])
        proc = run_store(self.data_dir, "delete-archived-activity", self._frozen(gone["id"]))
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertEqual(err["error"], "io")
        self.assertFalse(err.get("ok"))
        self.assertEqual(counts(self.data_dir, gone["id"]), before)
        got = decode(run_store(self.data_dir, "get", {"activity_id": gone["id"], "include_archived": True}))
        self.assertEqual(got["current"]["summary"], "Keep this checkpoint")
        self.assertEqual(got["draft"]["summary"], "Keep this draft")

    def test_unknown_activity_and_missing_cas_fields_are_validation(self) -> None:
        missing = run_store(
            self.data_dir,
            "delete-archived-activity",
            {
                "activity_id": "11111111-1111-1111-1111-111111111111",
                "expected_revision": 0,
                "expected_draft_revision": 0,
                "expected_archived_at": "2026-01-01T00:00:00Z",
                "expected_archive_generation": 0,
                "expected_name": "Missing",
            },
        )
        self.assertNotEqual(missing.returncode, 0)
        self.assertEqual(decode(missing)["error"], "validation")
        gone = self._create("No CAS")
        self._archive(gone["id"])
        incomplete = run_store(self.data_dir, "delete-archived-activity", {"activity_id": gone["id"]})
        self.assertNotEqual(incomplete.returncode, 0)
        self.assertEqual(decode(incomplete)["error"], "validation")
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 1)
        missing_generation = run_store(
            self.data_dir,
            "delete-archived-activity",
            {
                "activity_id": gone["id"],
                "expected_revision": 0,
                "expected_draft_revision": 0,
                "expected_archived_at": decode(run_store(self.data_dir, "get", {"activity_id": gone["id"], "include_archived": True}))["activity"]["archived_at"],
                "expected_name": "No CAS",
            },
        )
        self.assertNotEqual(missing_generation.returncode, 0)
        self.assertEqual(decode(missing_generation)["error"], "validation")
        self.assertEqual(counts(self.data_dir, gone["id"])["activities"], 1)

    def test_existing_v1_db_gains_archive_generation_without_losing_rows(self) -> None:
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
                created_at TEXT NOT NULL,
                archived_at TEXT
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
            INSERT INTO activities(id, name, created_at, archived_at)
            VALUES (
                '11111111-1111-4111-8111-111111111111',
                'Gone Trail Map',
                '2026-09-09T12:00:00Z',
                '2026-09-09T12:05:00Z'
            );
            INSERT INTO checkpoints(
                id, activity_id, revision, summary, next_step, context, state, author, saved_at
            ) VALUES (
                '22222222-2222-4222-8222-222222222222',
                '11111111-1111-4111-8111-111111111111',
                1,
                'Gone published trail notes',
                'Walk the ridge',
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
        activity_id = "11111111-1111-4111-8111-111111111111"
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity_id, "include_archived": True}))
        self.assertTrue(got.get("ok"), got)
        self.assertEqual(got["activity"]["name"], "Gone Trail Map")
        self.assertEqual(got["activity"]["archived_at"], "2026-09-09T12:05:00Z")
        self.assertEqual(got["activity"]["archive_generation"], 0)
        self.assertEqual(got["current"]["summary"], "Gone published trail notes")
        frozen_legacy = self._frozen(activity_id)
        self.assertEqual(frozen_legacy["expected_archive_generation"], 0)
        decode(run_store(self.data_dir, "unarchive-activity", {"activity_id": activity_id}))
        rearchived = decode(run_store(self.data_dir, "archive-activity", {"activity_id": activity_id}))
        self.assertTrue(rearchived.get("ok"), rearchived)
        conn = sqlite3.connect(db)
        conn.execute(
            "UPDATE activities SET archived_at = ? WHERE id = ?",
            ("2026-09-09T12:05:00Z", activity_id),
        )
        conn.commit()
        conn.close()
        stale = run_store(self.data_dir, "delete-archived-activity", frozen_legacy)
        self.assertNotEqual(stale.returncode, 0)
        err = decode(stale)
        self.assertEqual(err["error"], "stale_revision")
        self.assertGreater(err["current_archive_generation"], 0)
        still = decode(run_store(self.data_dir, "get", {"activity_id": activity_id, "include_archived": True}))
        self.assertEqual(still["current"]["summary"], "Gone published trail notes")
        current = self._frozen(activity_id)
        accepted = decode(run_store(self.data_dir, "delete-archived-activity", current))
        self.assertTrue(accepted.get("ok"), accepted)
        self.assertEqual(counts(self.data_dir, activity_id)["activities"], 0)


if __name__ == "__main__":
    unittest.main()
