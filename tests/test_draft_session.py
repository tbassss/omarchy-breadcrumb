#!/usr/bin/env python3
"""RED/GREEN overlapping-event tests for the draft UI scheduler.

Native/component timing seams must overlap (in-flight + keystroke +
navigation in the same turn). This module is the executable session
spec; Panel.qml implements the same identities and queue rules.
"""

from __future__ import annotations

import unittest

from draft_session import DraftSession


class TestDraftSession(unittest.TestCase):
    def test_delayed_autosave_with_keystrokes_and_navigation(self) -> None:
        session = DraftSession(activity_id="A")
        session.published_revision = 1
        session.published_summary = "Published lantern"
        session.draft_base_revision = 1
        session.type_text("autosave-v1")
        session.pump()
        self.assertIsNotNone(session.in_flight)
        self.assertEqual(session.in_flight.kind, "autosave")
        self.assertEqual(session.in_flight.edit_sequence, 1)
        self.assertEqual(session.in_flight.payload["summary"], "autosave-v1")
        session.type_text("autosave-v2-newer-keystrokes")
        session.navigate("B")
        self.assertEqual(session.editor, "autosave-v2-newer-keystrokes")
        self.assertEqual(session.activity_id, "A")
        self.assertEqual(session.nav_deferred_to, "B")
        self.assertTrue(session.nav_blocked_reason)
        session.complete_in_flight(
            {"ok": True, "draft": {"revision": 1, "base_revision": 1, "summary": "autosave-v1"}}
        )
        self.assertEqual(session.editor, "autosave-v2-newer-keystrokes")
        self.assertEqual(session.compensating_discards, [])
        self.assertTrue(session.pending_autosave)
        self.assertNotEqual(session.draft_status, "saved")
        if session.in_flight is None:
            session.pump()
        self.assertIsNotNone(session.in_flight)
        self.assertEqual(session.in_flight.kind, "autosave")
        self.assertEqual(session.in_flight.payload["summary"], "autosave-v2-newer-keystrokes")
        self.assertEqual(session.in_flight.edit_sequence, 2)
        session.complete_in_flight(
            {
                "ok": True,
                "draft": {
                    "revision": 2,
                    "base_revision": 1,
                    "summary": "autosave-v2-newer-keystrokes",
                },
            }
        )
        self.assertEqual(session.activity_id, "B")
        self.assertIsNone(session.nav_deferred_to)
        self.assertEqual(session.nav_blocked_reason, "")

    def test_explicit_save_behind_queued_autosave_is_not_dropped(self) -> None:
        session = DraftSession(activity_id="A")
        session.published_revision = 1
        session.published_summary = "Published lantern"
        session.draft_base_revision = 1
        session.type_text("queued-autosave")
        session.pump()
        session.type_text("explicit-save-text")
        session.save_checkpoint()
        session.type_text("later-autosave-must-not-drop-save")
        kinds = ([session.in_flight.kind] if session.in_flight else []) + [op.kind for op in session.queue]
        self.assertIn("publish", kinds)
        self.assertEqual(sum(1 for kind in kinds if kind == "publish"), 1)
        session.complete_in_flight(
            {"ok": True, "draft": {"revision": 1, "base_revision": 1, "summary": "queued-autosave"}}
        )
        if session.in_flight is None:
            session.pump()
        kinds = ([session.in_flight.kind] if session.in_flight else []) + [op.kind for op in session.queue]
        self.assertIn("publish", kinds)
        while session.in_flight is not None or session.queue:
            if session.in_flight is None:
                session.pump()
            op = session.in_flight
            self.assertIsNotNone(op)
            if op.kind == "autosave":
                session.complete_in_flight(
                    {
                        "ok": True,
                        "draft": {
                            "revision": session.draft_generation + 1,
                            "base_revision": 1,
                            "summary": op.payload["summary"],
                        },
                    }
                )
            elif op.kind == "publish":
                self.assertEqual(op.payload["summary"], "later-autosave-must-not-drop-save")
                self.assertEqual(op.payload["expected_revision"], 1)
                session.complete_in_flight(
                    {"ok": True, "revision": 2, "checkpoint": {"summary": op.payload["summary"]}}
                )
            else:
                self.fail("unexpected op " + op.kind)
        self.assertEqual(session.published_summary, "later-autosave-must-not-drop-save")
        self.assertEqual(session.published_revision, 2)

    def test_obsolete_discard_response_does_not_clobber_editor(self) -> None:
        session = DraftSession(activity_id="A")
        session.published_revision = 1
        session.published_summary = "Published lantern"
        session.draft_base_revision = 1
        session.type_text("draft-before-discard")
        session.pump()
        session.complete_in_flight(
            {
                "ok": True,
                "draft": {"revision": 1, "base_revision": 1, "summary": "draft-before-discard"},
            }
        )
        session.discard()
        session.pump()
        self.assertEqual(session.in_flight.kind, "discard")
        session.type_text("typed-during-discard")
        session.complete_in_flight({"ok": True, "draft": None, "draft_generation": 2})
        self.assertEqual(session.editor, "typed-during-discard")
        self.assertNotEqual(session.editor, "Published lantern")
        self.assertEqual(session.compensating_discards, [])
        self.assertTrue(session.dirty)
        self.assertTrue(session.pending_autosave)
        self.assertEqual(session.draft_generation, 2)

    def test_keep_editing_ordinary_save_uses_acknowledged_base(self) -> None:
        session = DraftSession(activity_id="A")
        session.published_revision = 1
        session.published_summary = "Published lantern v1"
        session.draft_base_revision = 1
        session.type_text("Keep-editing draft")
        session.pump()
        session.complete_in_flight(
            {
                "ok": True,
                "draft": {"revision": 1, "base_revision": 1, "summary": "Keep-editing draft"},
            }
        )
        session.note_external_publish(2, "Agent lantern v2")
        session.save_checkpoint()
        session.pump()
        self.assertEqual(session.in_flight.kind, "publish")
        self.assertEqual(session.in_flight.payload["expected_revision"], 1)
        session.complete_in_flight({"ok": False, "error": "stale_revision", "current_revision": 2})
        self.assertTrue(session.conflict_prompt)
        self.assertEqual(session.observed_revision, 2)
        self.assertEqual(session.draft_base_revision, 1)
        session.keep_editing()
        session.save_checkpoint()
        session.pump()
        self.assertEqual(session.in_flight.kind, "publish")
        self.assertEqual(session.in_flight.payload["expected_revision"], 1)
        session.complete_in_flight({"ok": False, "error": "stale_revision", "current_revision": 2})
        self.assertTrue(session.conflict_prompt)
        self.assertEqual(session.published_summary, "Agent lantern v2")
        session.resolve_save()
        session.pump()
        self.assertEqual(session.in_flight.kind, "resolve-publish")
        self.assertEqual(session.in_flight.payload["expected_revision"], 2)
        session.complete_in_flight(
            {"ok": True, "revision": 3, "checkpoint": {"summary": "Keep-editing draft"}}
        )
        self.assertEqual(session.published_revision, 3)
        self.assertEqual(session.published_summary, "Keep-editing draft")

    def test_delete_cancel_is_noop(self) -> None:
        session = DraftSession(activity_id="A")
        session.activity_name = "Gone Trail Map"
        session.archived = True
        session.archived_at = "2026-01-01T00:00:00Z"
        session.published_revision = 1
        session.published_summary = "Published lantern"
        session.editor = "Draft still here"
        session.has_live_draft = True
        session.dirty = True
        session.draft_generation = 2
        session.request_delete()
        self.assertEqual(session.delete_confirm["expected_name"], "Gone Trail Map")
        self.assertEqual(session.delete_confirm["expected_revision"], 1)
        self.assertEqual(session.delete_confirm["expected_draft_revision"], 2)
        session.cancel_delete()
        self.assertIsNone(session.delete_confirm)
        session.confirm_delete()
        session.pump()
        self.assertIsNone(session.in_flight)
        self.assertEqual(session.queue, [])
        self.assertEqual(session.editor, "Draft still here")
        self.assertTrue(session.has_live_draft)

    def test_delete_target_switch_clears_confirmation(self) -> None:
        session = DraftSession(activity_id="A")
        session.activity_name = "Gone Trail Map"
        session.archived = True
        session.archived_at = "2026-01-01T00:00:00Z"
        session.published_revision = 1
        session.request_delete()
        session.navigate("B")
        self.assertIsNone(session.delete_confirm)
        self.assertEqual(session.activity_id, "B")
        session.confirm_delete()
        session.pump()
        self.assertIsNone(session.in_flight)
        self.assertEqual(session.queue, [])

    def test_delete_last_activity_clears_selection(self) -> None:
        session = DraftSession(activity_id="A")
        session.activity_name = "Only Trail"
        session.archived = True
        session.archived_at = "2026-01-01T00:00:00Z"
        session.published_revision = 1
        session.editor = "Last draft"
        session.has_live_draft = True
        session.draft_generation = 1
        session.request_delete()
        session.confirm_delete()
        session.pump()
        self.assertEqual(session.in_flight.kind, "delete-archived")
        self.assertEqual(session.in_flight.payload["expected_name"], "Only Trail")
        session.complete_in_flight(
            {"ok": True, "deleted_activity_id": "A", "selected_activity_id": None}
        )
        self.assertEqual(session.activity_id, "")
        self.assertFalse(session.has_live_draft)
        self.assertFalse(session.dirty)
        self.assertEqual(session.editor, "")
        self.assertIsNone(session.delete_confirm)

    def test_delete_sends_frozen_tokens_and_failed_delete_keeps_draft(self) -> None:
        session = DraftSession(activity_id="A")
        session.activity_name = "Stale Trail"
        session.archived = True
        session.archived_at = "2026-01-01T00:00:00Z"
        session.published_revision = 1
        session.draft_generation = 0
        session.editor = "Keep this draft"
        session.has_live_draft = True
        session.dirty = True
        session.request_delete()
        session.published_revision = 2
        session.draft_generation = 4
        session.confirm_delete()
        session.pump()
        op = session.in_flight
        self.assertEqual(op.kind, "delete-archived")
        self.assertEqual(op.payload["expected_revision"], 1)
        self.assertEqual(op.payload["expected_draft_revision"], 0)
        self.assertEqual(op.payload["expected_archived_at"], "2026-01-01T00:00:00Z")
        self.assertEqual(op.payload["expected_archive_generation"], 0)
        session.complete_in_flight(
            {"ok": False, "error": "stale_revision", "current_revision": 2, "expected_revision": 1}
        )
        self.assertEqual(session.editor, "Keep this draft")
        self.assertTrue(session.has_live_draft)
        self.assertEqual(session.draft_status, "error")
        self.assertEqual(session.last_error, "stale_revision")

    def test_queued_autosave_after_delete_does_not_resurrect(self) -> None:
        session = DraftSession(activity_id="A")
        session.activity_name = "Gone Trail Map"
        session.archived = True
        session.archived_at = "2026-01-01T00:00:00Z"
        session.published_revision = 1
        session.editor = "draft-v1"
        session.has_live_draft = True
        session.dirty = True
        session.request_delete()
        session.confirm_delete()
        session.type_text("draft-v2-must-not-resurrect")
        kinds = ([session.in_flight.kind] if session.in_flight else []) + [op.kind for op in session.queue]
        self.assertIn("delete-archived", kinds)
        session.pump()
        if session.in_flight and session.in_flight.kind != "delete-archived":
            session.queue = [session.in_flight, *session.queue]
            session.in_flight = None
            session.queue = [op for op in session.queue if op.kind == "delete-archived"] + [
                op for op in session.queue if op.kind != "delete-archived"
            ]
            session.pump()
        self.assertEqual(session.in_flight.kind, "delete-archived")
        session.complete_in_flight(
            {"ok": True, "deleted_activity_id": "A", "selected_activity_id": None}
        )
        kinds = ([session.in_flight.kind] if session.in_flight else []) + [op.kind for op in session.queue]
        self.assertNotIn("autosave", kinds)
        self.assertEqual(session.activity_id, "")
        self.assertFalse(session.has_live_draft)

    def test_unarchive_clears_delete_confirm_and_keeps_draft(self) -> None:
        session = DraftSession(activity_id="A")
        session.activity_name = "Gone Trail Map"
        session.archived = True
        session.archived_at = "2026-01-01T00:00:00Z"
        session.published_revision = 2
        session.published_summary = "Second trail checkpoint"
        session.editor = "Gone durable draft must survive unarchive"
        session.has_live_draft = True
        session.dirty = True
        session.draft_generation = 3
        session.request_delete()
        self.assertIsNotNone(session.delete_confirm)
        session.unarchive()
        self.assertIsNone(session.delete_confirm)
        session.confirm_delete()
        session.pump()
        self.assertEqual(session.in_flight.kind, "unarchive")
        self.assertEqual(session.in_flight.payload["activity_id"], "A")
        session.complete_in_flight({"ok": True, "activity": {"id": "A", "archived_at": None}})
        self.assertFalse(session.archived)
        self.assertEqual(session.archived_at, "")
        self.assertEqual(session.editor, "Gone durable draft must survive unarchive")
        self.assertTrue(session.has_live_draft)
        self.assertEqual(session.published_revision, 2)
        self.assertIsNone(session.delete_confirm)
        session.request_delete()
        self.assertIsNone(session.delete_confirm)

    def test_delete_in_flight_then_unarchive_does_not_resurrect(self) -> None:
        session = DraftSession(activity_id="A")
        session.activity_name = "Gone Trail Map"
        session.archived = True
        session.archived_at = "2026-01-01T00:00:00Z"
        session.published_revision = 1
        session.editor = "Draft still here"
        session.has_live_draft = True
        session.request_delete()
        session.confirm_delete()
        session.pump()
        self.assertEqual(session.in_flight.kind, "delete-archived")
        session.unarchive()
        session.complete_in_flight(
            {"ok": True, "deleted_activity_id": "A", "selected_activity_id": None}
        )
        self.assertEqual(session.activity_id, "")
        self.assertFalse(session.has_live_draft)
        session.pump()
        self.assertEqual(session.in_flight.kind, "unarchive")
        session.complete_in_flight({"ok": False, "error": "validation"})
        self.assertEqual(session.activity_id, "")
        self.assertFalse(session.archived)
        self.assertEqual(session.editor, "")

    def test_failed_unarchive_keeps_archived_draft(self) -> None:
        session = DraftSession(activity_id="A")
        session.archived = True
        session.archived_at = "2026-01-01T00:00:00Z"
        session.editor = "Keep this draft"
        session.has_live_draft = True
        session.dirty = True
        session.unarchive()
        session.pump()
        session.complete_in_flight({"ok": False, "error": "io"})
        self.assertTrue(session.archived)
        self.assertEqual(session.archived_at, "2026-01-01T00:00:00Z")
        self.assertEqual(session.editor, "Keep this draft")
        self.assertTrue(session.has_live_draft)
        self.assertEqual(session.last_error, "io")


if __name__ == "__main__":
    unittest.main()
