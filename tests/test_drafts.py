#!/usr/bin/env python3
"""Behavioral tests for crash-safe per-activity drafts (issue #5)."""

from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from test_store import decode, run_store

STORE = Path(__file__).resolve().parents[1] / "bin" / "breadcrumb-store"


class TestDrafts(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory(prefix="breadcrumb-draft-")
        self.data_dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_save_draft_persists_without_publishing_history(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        proc = run_store(
            self.data_dir,
            "save-draft",
            {
                "activity_id": activity["id"],
                "expected_draft_revision": 0,
                "base_revision": 0,
                "summary": "Halfway through the routing notes",
                "next_step": "Finish the subnetting set",
                "context": "Fictional course draft only.",
                "state": "in_progress",
                "author": "You",
            },
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertTrue(body.get("ok"), body)
        draft = body["draft"]
        self.assertEqual(draft["revision"], 1)
        self.assertEqual(draft["base_revision"], 0)
        self.assertEqual(draft["summary"], "Halfway through the routing notes")
        self.assertEqual(draft["next_step"], "Finish the subnetting set")
        self.assertEqual(draft["context"], "Fictional course draft only.")
        self.assertEqual(draft["state"], "in_progress")
        self.assertEqual(draft["author"], "You")
        self.assertEqual(draft["activity_id"], activity["id"])
        self.assertTrue(draft["updated_at"].endswith("Z"))
        self.assertEqual(draft.get("links") or [], [])

        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertTrue(got.get("ok"), got)
        self.assertIsNone(got["current"])
        self.assertEqual(got["revision"], 0)
        self.assertEqual(got["draft"]["summary"], "Halfway through the routing notes")
        self.assertEqual(got["draft"]["revision"], 1)
        self.assertEqual(got["history"]["entries"], [])

        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        checkpoint_count = conn.execute("SELECT COUNT(*) FROM checkpoints").fetchone()[0]
        conn.close()
        self.assertEqual(checkpoint_count, 0)

    def _save_draft(
        self,
        activity_id: str,
        expected: int,
        summary: str,
        *,
        base_revision: int = 0,
        next_step: str = "Keep going",
        context: str = "Fictional draft.",
        state: str = "in_progress",
        author: str = "You",
        links: list | None = None,
        acknowledge_base: bool | None = None,
        observed_revision: int | None = None,
    ) -> subprocess.CompletedProcess[str]:
        payload = {
            "activity_id": activity_id,
            "expected_draft_revision": expected,
            "base_revision": base_revision,
            "summary": summary,
            "next_step": next_step,
            "context": context,
            "state": state,
            "author": author,
        }
        if links is not None:
            payload["links"] = links
        if acknowledge_base is not None:
            payload["acknowledge_base"] = acknowledge_base
        if observed_revision is not None:
            payload["observed_revision"] = observed_revision
        return run_store(self.data_dir, "save-draft", payload)

    def test_stale_save_draft_does_not_overwrite_newer_draft(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        first = decode(self._save_draft(activity["id"], 0, "First draft"))
        self.assertEqual(first["draft"]["revision"], 1)
        second = decode(self._save_draft(activity["id"], 1, "Second draft"))
        self.assertEqual(second["draft"]["revision"], 2)
        stale = self._save_draft(activity["id"], 1, "Stale delayed draft")
        self.assertNotEqual(stale.returncode, 0)
        err = decode(stale)
        self.assertFalse(err.get("ok"))
        self.assertEqual(err["error"], "stale_revision")
        self.assertEqual(err["current_draft_revision"], 2)
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(got["draft"]["summary"], "Second draft")
        self.assertEqual(got["draft"]["revision"], 2)
        self.assertNotEqual(got["draft"]["summary"], "Stale delayed draft")

    def test_discard_draft_removes_draft_and_stale_save_does_not_resurrect(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        saved = decode(self._save_draft(activity["id"], 0, "Draft to discard"))
        self.assertEqual(saved["draft"]["revision"], 1)
        discarded = run_store(
            self.data_dir,
            "discard-draft",
            {"activity_id": activity["id"], "expected_draft_revision": 1},
        )
        self.assertEqual(discarded.returncode, 0, discarded.stderr)
        body = decode(discarded)
        self.assertTrue(body.get("ok"), body)
        self.assertIsNone(body["draft"])
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertIsNone(got["draft"])
        resurrect = self._save_draft(activity["id"], 1, "Should not come back")
        self.assertNotEqual(resurrect.returncode, 0)
        err = decode(resurrect)
        self.assertEqual(err["error"], "stale_revision")
        self.assertEqual(err["current_draft_revision"], 2)
        still = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertIsNone(still["draft"])
        self.assertEqual(still["draft_generation"], 2)
        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        row = conn.execute("SELECT revision, live FROM drafts WHERE activity_id = ?", (activity["id"],)).fetchone()
        conn.close()
        self.assertIsNotNone(row)
        self.assertEqual(row[0], 2)
        self.assertEqual(row[1], 0)

    def _publish(
        self,
        activity_id: str,
        expected: int,
        summary: str,
        next_step: str = "Keep going",
        *,
        consume_draft_revision: int | None = None,
    ) -> dict:
        payload = {
            "activity_id": activity_id,
            "expected_revision": expected,
            "summary": summary,
            "next_step": next_step,
            "state": "in_progress",
            "author": "You",
        }
        if consume_draft_revision is not None:
            payload["consume_draft_revision"] = consume_draft_revision
        proc = run_store(self.data_dir, "publish", payload)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        body = decode(proc)
        self.assertTrue(body.get("ok"), body)
        return body

    def test_publish_clears_draft_and_stale_save_does_not_resurrect(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        decode(self._save_draft(activity["id"], 0, "Unpublished draft"))
        published = self._publish(activity["id"], 0, "Published checkpoint", consume_draft_revision=1)
        self.assertEqual(published["revision"], 1)
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(got["current"]["summary"], "Published checkpoint")
        self.assertIsNone(got["draft"])
        resurrect = self._save_draft(activity["id"], 1, "Should not come back after publish")
        self.assertNotEqual(resurrect.returncode, 0)
        err = decode(resurrect)
        self.assertEqual(err["error"], "stale_revision")
        self.assertEqual(err["current_draft_revision"], 2)
        still = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertIsNone(still["draft"])
        self.assertEqual(still["draft_generation"], 2)
        self.assertEqual(still["current"]["summary"], "Published checkpoint")
        self.assertEqual(len(still["history"]["entries"]), 1)

    def test_stale_publish_preserves_newer_publication_and_draft(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        first = self._publish(activity["id"], 0, "First checkpoint")
        decode(self._save_draft(activity["id"], 0, "Local draft against revision 1", base_revision=1))
        newer = self._publish(activity["id"], 1, "Newer published checkpoint")
        self.assertEqual(newer["revision"], 2)
        stale = run_store(
            self.data_dir,
            "publish",
            {
                "activity_id": activity["id"],
                "expected_revision": 1,
                "summary": "Stale save from the draft",
                "next_step": "Should not land",
                "state": "waiting",
                "author": "You",
            },
        )
        self.assertEqual(stale.returncode, 4)
        err = decode(stale)
        self.assertEqual(err["error"], "stale_revision")
        self.assertEqual(err["current_revision"], 2)
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(got["current"]["id"], newer["current"]["id"])
        self.assertEqual(got["current"]["summary"], "Newer published checkpoint")
        self.assertNotEqual(got["current"]["id"], first["current"]["id"])
        self.assertEqual(got["draft"]["summary"], "Local draft against revision 1")
        self.assertEqual(got["draft"]["base_revision"], 1)
        self.assertEqual(got["revision"], 2)

    def test_concurrent_external_publish_and_save_draft_preserve_both(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        first = self._publish(activity["id"], 0, "First checkpoint")

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

        publish_payload = {
            "activity_id": activity["id"],
            "expected_revision": 1,
            "summary": "Agent published while drafting",
            "next_step": "Review the conflict",
            "state": "in_progress",
            "author": "Agent",
        }
        draft_payload = {
            "activity_id": activity["id"],
            "expected_draft_revision": 0,
            "base_revision": 1,
            "summary": "Local draft during agent publish",
            "next_step": "Keep this draft",
            "context": "Fictional concurrent draft.",
            "state": "in_progress",
            "author": "You",
        }
        left = start("publish", publish_payload)
        right = start("save-draft", draft_payload)
        left_out, left_err = left.communicate(timeout=15)
        right_out, right_err = right.communicate(timeout=15)
        self.assertEqual(left.returncode, 0, left_err + left_out)
        self.assertEqual(right.returncode, 0, right_err + right_out)
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(got["revision"], 2)
        self.assertEqual(got["current"]["summary"], "Agent published while drafting")
        self.assertNotEqual(got["current"]["id"], first["current"]["id"])
        self.assertEqual(got["draft"]["summary"], "Local draft during agent publish")
        self.assertEqual(got["draft"]["base_revision"], 1)

    def test_concurrent_save_draft_cas_keeps_one_winner(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]

        def start(summary: str) -> subprocess.Popen[str]:
            env = os.environ.copy()
            env["BREADCRUMB_DATA_DIR"] = str(self.data_dir)
            env["PYTHONDONTWRITEBYTECODE"] = "1"
            payload = {
                "activity_id": activity["id"],
                "expected_draft_revision": 0,
                "base_revision": 0,
                "summary": summary,
                "next_step": "Keep going",
                "state": "in_progress",
                "author": "You",
            }
            return subprocess.Popen(
                [sys.executable, str(STORE), "save-draft", json.dumps(payload)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
            )

        left = start("Draft A")
        right = start("Draft B")
        left_out, left_err = left.communicate(timeout=15)
        right_out, right_err = right.communicate(timeout=15)
        codes = sorted([left.returncode, right.returncode])
        self.assertEqual(codes, [0, 4], f"{left_out!r} {left_err!r} {right_out!r} {right_err!r}")
        winner = json.loads(left_out if left.returncode == 0 else right_out)
        self.assertEqual(winner["draft"]["revision"], 1)
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(got["draft"]["revision"], 1)
        self.assertIn(got["draft"]["summary"], ("Draft A", "Draft B"))

    def test_existing_v1_database_gains_drafts_without_losing_rows(self) -> None:
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

        got = decode(
            run_store(self.data_dir, "get", {"activity_id": "11111111-1111-4111-8111-111111111111"})
        )
        self.assertTrue(got.get("ok"), got)
        self.assertEqual(got["current"]["summary"], "Finished the routing lesson")
        self.assertIsNone(got["draft"])
        saved = decode(
            self._save_draft(
                "11111111-1111-4111-8111-111111111111",
                0,
                "Draft on migrated v1",
                base_revision=1,
            )
        )
        self.assertEqual(saved["draft"]["revision"], 1)
        reopened = decode(
            run_store(self.data_dir, "get", {"activity_id": "11111111-1111-4111-8111-111111111111"})
        )
        self.assertEqual(reopened["current"]["summary"], "Finished the routing lesson")
        self.assertEqual(reopened["draft"]["summary"], "Draft on migrated v1")

    def test_save_draft_permission_error_keeps_prior_draft(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        decode(self._save_draft(activity["id"], 0, "Prior draft"))
        db = self.data_dir / "breadcrumb.sqlite"
        os.chmod(db, 0o000)
        try:
            proc = self._save_draft(activity["id"], 1, "Should fail")
        finally:
            os.chmod(db, 0o600)
        self.assertNotEqual(proc.returncode, 0)
        err = decode(proc)
        self.assertFalse(err.get("ok"))
        self.assertEqual(err["error"], "permission")
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(got["draft"]["summary"], "Prior draft")
        self.assertEqual(got["draft"]["revision"], 1)

    def test_incomplete_draft_and_activity_isolation(self) -> None:
        study = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        app = decode(run_store(self.data_dir, "create-activity", {"name": "App Project"}))["activity"]
        incomplete = decode(
            self._save_draft(study["id"], 0, "", next_step="", context="", state="ready")
        )
        self.assertEqual(incomplete["draft"]["summary"], "")
        decode(
            self._save_draft(
                app["id"],
                0,
                "App draft",
                links=[{"label": "Notes", "kind": "web", "target": "https://example.com/notes"}],
            )
        )
        study_get = decode(run_store(self.data_dir, "get", {"activity_id": study["id"]}))
        app_get = decode(run_store(self.data_dir, "get", {"activity_id": app["id"]}))
        self.assertEqual(study_get["draft"]["summary"], "")
        self.assertEqual(app_get["draft"]["summary"], "App draft")
        self.assertEqual(app_get["draft"]["links"][0]["target"], "https://example.com/notes")
        self.assertNotEqual(study_get["activity"]["id"], app_get["activity"]["id"])

    def test_resolution_publish_uses_observed_revision_and_consumes_matching_draft(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        self._publish(activity["id"], 0, "First checkpoint")
        decode(self._save_draft(activity["id"], 0, "Draft to keep as new checkpoint", base_revision=1))
        newer = self._publish(activity["id"], 1, "Agent checkpoint")
        observed = newer["revision"]
        resolved = self._publish(
            activity["id"],
            observed,
            "Draft to keep as new checkpoint",
            consume_draft_revision=1,
        )
        self.assertEqual(resolved["revision"], observed + 1)
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(got["current"]["summary"], "Draft to keep as new checkpoint")
        self.assertIsNone(got["draft"])
        implicit = run_store(
            self.data_dir,
            "publish",
            {
                "activity_id": activity["id"],
                "expected_revision": 1,
                "summary": "Implicit overwrite",
                "next_step": "No",
                "state": "in_progress",
                "author": "You",
            },
        )
        self.assertEqual(implicit.returncode, 4)
        still = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(still["current"]["summary"], "Draft to keep as new checkpoint")

    def test_discard_missing_draft_is_idempotent_and_stale_discard_keeps_newer(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        missing = run_store(
            self.data_dir,
            "discard-draft",
            {"activity_id": activity["id"], "expected_draft_revision": 0},
        )
        self.assertEqual(missing.returncode, 0, missing.stderr)
        self.assertIsNone(decode(missing)["draft"])
        decode(self._save_draft(activity["id"], 0, "Kept draft"))
        decode(self._save_draft(activity["id"], 1, "Newer draft"))
        stale = run_store(
            self.data_dir,
            "discard-draft",
            {"activity_id": activity["id"], "expected_draft_revision": 1},
        )
        self.assertEqual(stale.returncode, 4)
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(got["draft"]["summary"], "Newer draft")
        self.assertEqual(got["draft"]["revision"], 2)

    def test_ordinary_save_draft_cannot_advance_acknowledged_base(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        self._publish(activity["id"], 0, "Published lantern v1")
        first = decode(self._save_draft(activity["id"], 0, "Draft against v1", base_revision=1))
        self.assertEqual(first["draft"]["base_revision"], 1)
        self._publish(activity["id"], 1, "Published lantern v2")
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(got["revision"], 2)
        self.assertEqual(got["draft"]["base_revision"], 1)
        rebase = self._save_draft(activity["id"], 1, "Silently adopted v2", base_revision=2)
        self.assertEqual(rebase.returncode, 4, rebase.stdout)
        err = decode(rebase)
        self.assertEqual(err["error"], "stale_revision")
        self.assertEqual(err.get("current_base_revision"), 1)
        still = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(still["draft"]["summary"], "Draft against v1")
        self.assertEqual(still["draft"]["base_revision"], 1)
        self.assertEqual(still["current"]["summary"], "Published lantern v2")
        updated = decode(self._save_draft(activity["id"], 1, "Still against v1", base_revision=1))
        self.assertEqual(updated["draft"]["base_revision"], 1)
        self.assertEqual(updated["draft"]["summary"], "Still against v1")

    def test_refresh_old_base_publish_conflicts_until_acknowledged_observed(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        self._publish(activity["id"], 0, "Published lantern v1")
        decode(self._save_draft(activity["id"], 0, "Keep-editing draft", base_revision=1))
        self._publish(activity["id"], 1, "Agent lantern v2")
        ordinary = run_store(
            self.data_dir,
            "publish",
            {
                "activity_id": activity["id"],
                "expected_revision": 1,
                "summary": "Keep-editing draft",
                "next_step": "Keep going",
                "state": "in_progress",
                "author": "You",
                "consume_draft_revision": 1,
            },
        )
        self.assertEqual(ordinary.returncode, 4)
        after_keep = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(after_keep["current"]["summary"], "Agent lantern v2")
        self.assertEqual(after_keep["draft"]["summary"], "Keep-editing draft")
        self.assertEqual(after_keep["draft"]["base_revision"], 1)
        stale_ack = self._save_draft(
            activity["id"],
            1,
            "Keep-editing draft",
            base_revision=2,
            acknowledge_base=True,
            observed_revision=1,
        )
        self.assertEqual(stale_ack.returncode, 4, stale_ack.stdout)
        ack = decode(
            self._save_draft(
                activity["id"],
                1,
                "Keep-editing draft",
                base_revision=2,
                acknowledge_base=True,
                observed_revision=2,
            )
        )
        self.assertEqual(ack["draft"]["base_revision"], 2)
        resolved = self._publish(
            activity["id"],
            2,
            "Keep-editing draft",
            consume_draft_revision=ack["draft"]["revision"],
        )
        self.assertEqual(resolved["revision"], 3)
        done = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(done["current"]["summary"], "Keep-editing draft")
        self.assertIsNone(done["draft"])

    def test_discard_recreate_generation_aba_stale_discard_keeps_new_draft(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        first = decode(self._save_draft(activity["id"], 0, "Original draft"))
        self.assertEqual(first["draft"]["revision"], 1)
        discarded = run_store(
            self.data_dir,
            "discard-draft",
            {"activity_id": activity["id"], "expected_draft_revision": 1},
        )
        self.assertEqual(discarded.returncode, 0, discarded.stderr)
        discarded_body = decode(discarded)
        self.assertIsNone(discarded_body["draft"])
        tombstone_generation = discarded_body.get("draft_generation")
        self.assertIsInstance(tombstone_generation, int)
        self.assertGreater(tombstone_generation, 0)
        got = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertIsNone(got["draft"])
        self.assertEqual(got.get("draft_generation"), tombstone_generation)
        recreated = decode(
            self._save_draft(
                activity["id"],
                tombstone_generation,
                "New draft after discard",
                base_revision=0,
            )
        )
        self.assertGreater(recreated["draft"]["revision"], tombstone_generation)
        stale = run_store(
            self.data_dir,
            "discard-draft",
            {"activity_id": activity["id"], "expected_draft_revision": 1},
        )
        self.assertEqual(stale.returncode, 4, stale.stdout)
        still = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(still["draft"]["summary"], "New draft after discard")
        conn = sqlite3.connect(self.data_dir / "breadcrumb.sqlite")
        row = conn.execute(
            "SELECT revision, live FROM drafts WHERE activity_id = ?",
            (activity["id"],),
        ).fetchone()
        conn.close()
        self.assertIsNotNone(row)
        self.assertEqual(row[0], recreated["draft"]["revision"])
        self.assertEqual(row[1], 1)

    def test_stale_consume_after_discard_recreate_does_not_delete_new_draft(self) -> None:
        activity = decode(run_store(self.data_dir, "create-activity", {"name": "Study"}))["activity"]
        self._publish(activity["id"], 0, "Published lantern v1")
        decode(self._save_draft(activity["id"], 0, "Old draft", base_revision=1))
        discarded = decode(
            run_store(
                self.data_dir,
                "discard-draft",
                {"activity_id": activity["id"], "expected_draft_revision": 1},
            )
        )
        tombstone_generation = discarded["draft_generation"]
        recreated = decode(
            self._save_draft(
                activity["id"],
                tombstone_generation,
                "New draft after discard",
                base_revision=1,
            )
        )
        stale_consume = run_store(
            self.data_dir,
            "publish",
            {
                "activity_id": activity["id"],
                "expected_revision": 1,
                "summary": "Stale consume publish",
                "next_step": "No",
                "state": "in_progress",
                "author": "You",
                "consume_draft_revision": 1,
            },
        )
        self.assertEqual(stale_consume.returncode, 4, stale_consume.stdout)
        err = decode(stale_consume)
        self.assertEqual(err["error"], "stale_revision")
        still = decode(run_store(self.data_dir, "get", {"activity_id": activity["id"]}))
        self.assertEqual(still["current"]["summary"], "Published lantern v1")
        self.assertEqual(still["revision"], 1)
        self.assertEqual(still["draft"]["summary"], "New draft after discard")
        self.assertEqual(still["draft"]["revision"], recreated["draft"]["revision"])


if __name__ == "__main__":
    unittest.main()
