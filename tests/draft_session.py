"""Deterministic draft UI session scheduler.

Identities stay separate:
- published_revision: checkpoint CAS token
- draft_generation: durable per-activity generation, including tombstones
- edit_sequence: editor keystroke sequence
- request snapshot: immutable activity/kind/sequence captured at enqueue,
  with CAS tokens and editor payload bound at send time

The queue serializes store mutations. Unsent autosaves for the same
activity may coalesce. Explicit save/discard/navigation are never dropped.
Stale responses never clobber the editor or issue compensating discards.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class Op:
    kind: str
    activity_id: str
    edit_sequence: int
    payload: dict = field(default_factory=dict)


class DraftSession:
    def __init__(self, activity_id: str = "A") -> None:
        self.activity_id = activity_id
        self.published_revision = 0
        self.published_summary = ""
        self.draft_generation = 0
        self.draft_base_revision = 0
        self.has_live_draft = False
        self.edit_sequence = 0
        self.editor = ""
        self.dirty = False
        self.pending_autosave = False
        self.draft_status = ""
        self.observed_revision = 0
        self.conflict_prompt = False
        self.queue: list[Op] = []
        self.in_flight: Op | None = None
        self.nav_deferred_to: str | None = None
        self.nav_blocked_reason = ""
        self.compensating_discards: list[Any] = []
        self.acked_sequences: list[int] = []
        self.delete_confirm: dict | None = None
        self.activity_name = ""
        self.archived = False
        self.archived_at = ""
        self.last_error = ""

    def type_text(self, text: str) -> None:
        if not self.has_live_draft and not self.dirty:
            self.draft_base_revision = self.published_revision
        self.edit_sequence += 1
        self.editor = text
        self.dirty = True
        self.has_live_draft = True
        self.pending_autosave = True
        self.draft_status = ""
        self.enqueue(Op(kind="autosave", activity_id=self.activity_id, edit_sequence=self.edit_sequence, payload={"summary": text}))

    def enqueue(self, op: Op) -> None:
        if op.kind == "autosave":
            for index, existing in enumerate(self.queue):
                if existing.kind == "autosave" and existing.activity_id == op.activity_id:
                    self.queue[index] = op
                    return
        self.queue.append(op)

    def pump(self) -> None:
        if self.in_flight is not None or not self.queue:
            return
        op = self.queue.pop(0)
        if op.kind == "autosave":
            op.payload = {
                "summary": self.editor if op.activity_id == self.activity_id else op.payload.get("summary", ""),
                "expected_draft_revision": self.draft_generation,
                "base_revision": self.draft_base_revision,
            }
            op.edit_sequence = self.edit_sequence if op.activity_id == self.activity_id else op.edit_sequence
            self.draft_status = "saving"
        elif op.kind == "publish":
            op.payload = {
                "summary": self.editor,
                "expected_revision": self.draft_base_revision if (self.has_live_draft or self.dirty) else self.published_revision,
                "consume_draft_revision": self.draft_generation if self.has_live_draft else None,
            }
        elif op.kind == "resolve-publish":
            op.payload = {
                "summary": self.editor,
                "expected_revision": self.observed_revision,
                "consume_draft_revision": self.draft_generation if self.has_live_draft else None,
            }
        elif op.kind == "discard":
            op.payload = {"expected_draft_revision": self.draft_generation}
        self.in_flight = op

    def complete_in_flight(self, result: dict) -> None:
        op = self.in_flight
        self.in_flight = None
        if op is None:
            return
        if op.kind == "autosave":
            self._ack_autosave(op, result)
        elif op.kind == "discard":
            self._ack_discard(op, result)
        elif op.kind in ("publish", "resolve-publish"):
            self._ack_publish(op, result)
        elif op.kind == "delete-archived":
            self._ack_delete(op, result)
        elif op.kind == "unarchive":
            self._ack_unarchive(op, result)
        self.pump()
        self._maybe_finish_nav()

    def _ack_autosave(self, op: Op, result: dict) -> None:
        if not result.get("ok"):
            self.draft_status = "error"
            self.nav_deferred_to = None
            self.nav_blocked_reason = ""
            return
        draft = result.get("draft") or {}
        if op.activity_id != self.activity_id:
            return
        if draft.get("revision") is not None:
            self.draft_generation = int(draft["revision"])
            self.draft_base_revision = int(draft.get("base_revision", self.draft_base_revision))
            self.has_live_draft = True
        self.acked_sequences.append(op.edit_sequence)
        if self.edit_sequence == op.edit_sequence:
            self.pending_autosave = False
            self.draft_status = "saved"
            self.dirty = False
        else:
            self.pending_autosave = True
            self.draft_status = ""
            self.enqueue(
                Op(
                    kind="autosave",
                    activity_id=self.activity_id,
                    edit_sequence=self.edit_sequence,
                    payload={"summary": self.editor},
                )
            )

    def _ack_discard(self, op: Op, result: dict) -> None:
        generation = result.get("draft_generation")
        if generation is not None:
            self.draft_generation = int(generation)
        if op.activity_id != self.activity_id:
            return
        if self.edit_sequence != op.edit_sequence:
            self.has_live_draft = True
            self.dirty = True
            self.pending_autosave = True
            self.enqueue(
                Op(
                    kind="autosave",
                    activity_id=self.activity_id,
                    edit_sequence=self.edit_sequence,
                    payload={"summary": self.editor},
                )
            )
            return
        self.has_live_draft = False
        self.dirty = False
        self.pending_autosave = False
        self.draft_status = ""
        self.editor = self.published_summary
        self.draft_base_revision = self.published_revision

    def _ack_publish(self, op: Op, result: dict) -> None:
        if not result.get("ok"):
            if result.get("error") == "stale_revision":
                self.conflict_prompt = True
                self.observed_revision = int(result.get("current_revision") or self.published_revision)
            return
        self.published_revision = int(result.get("revision", self.published_revision + 1))
        checkpoint = result.get("checkpoint") or {}
        self.published_summary = checkpoint.get("summary", op.payload.get("summary", self.editor))
        self.has_live_draft = False
        self.dirty = False
        self.pending_autosave = False
        self.conflict_prompt = False
        self.draft_status = ""
        self.draft_base_revision = self.published_revision

    def _ack_delete(self, op: Op, result: dict) -> None:
        if not result.get("ok"):
            self.draft_status = "error"
            self.last_error = str(result.get("error") or "error")
            return
        self.queue = [
            item for item in self.queue
            if not (item.kind == "autosave" and item.activity_id == op.activity_id)
        ]
        self.delete_confirm = None
        selected = result.get("selected_activity_id")
        if selected:
            self.activity_id = str(selected)
            self.archived = False
            self.archived_at = ""
            self.activity_name = ""
            self.has_live_draft = False
            self.dirty = False
            self.pending_autosave = False
            self.editor = ""
            self.draft_status = ""
            self.draft_generation = 0
            self.published_revision = 0
            self.published_summary = ""
            return
        self.activity_id = ""
        self.archived = False
        self.archived_at = ""
        self.activity_name = ""
        self.has_live_draft = False
        self.dirty = False
        self.pending_autosave = False
        self.editor = ""
        self.draft_status = ""
        self.draft_generation = 0
        self.published_revision = 0
        self.published_summary = ""

    def _ack_unarchive(self, op: Op, result: dict) -> None:
        if not result.get("ok"):
            self.draft_status = "error"
            self.last_error = str(result.get("error") or "error")
            return
        if op.activity_id != self.activity_id:
            return
        self.archived = False
        self.archived_at = ""
        self.delete_confirm = None

    def save_checkpoint(self) -> None:
        self.enqueue(Op(kind="publish", activity_id=self.activity_id, edit_sequence=self.edit_sequence, payload={}))

    def resolve_save(self) -> None:
        self.enqueue(Op(kind="resolve-publish", activity_id=self.activity_id, edit_sequence=self.edit_sequence, payload={}))

    def keep_editing(self) -> None:
        self.conflict_prompt = False

    def discard(self) -> None:
        self.queue = [op for op in self.queue if not (op.kind == "autosave" and op.activity_id == self.activity_id)]
        self.enqueue(Op(kind="discard", activity_id=self.activity_id, edit_sequence=self.edit_sequence, payload={}))

    def navigate(self, activity_id: str) -> None:
        self.delete_confirm = None
        if activity_id == self.activity_id:
            return
        if self._needs_flush():
            self.nav_deferred_to = activity_id
            self.nav_blocked_reason = "Saving draft…"
            self.draft_status = "saving"
            self.enqueue(
                Op(
                    kind="autosave",
                    activity_id=self.activity_id,
                    edit_sequence=self.edit_sequence,
                    payload={"summary": self.editor},
                )
            )
            return
        self.activity_id = activity_id
        self.nav_deferred_to = None
        self.nav_blocked_reason = ""

    def note_external_publish(self, revision: int, summary: str) -> None:
        self.published_revision = revision
        self.published_summary = summary

    def _needs_flush(self) -> bool:
        if self.dirty or self.pending_autosave:
            return True
        if self.in_flight is not None and self.in_flight.kind == "autosave" and self.in_flight.activity_id == self.activity_id:
            return True
        return any(op.kind == "autosave" and op.activity_id == self.activity_id for op in self.queue)

    def _maybe_finish_nav(self) -> None:
        if self.nav_deferred_to is None:
            return
        if self._needs_flush():
            return
        self.activity_id = self.nav_deferred_to
        self.nav_deferred_to = None
        self.nav_blocked_reason = ""

    def request_delete(self) -> None:
        if not self.archived:
            return
        self.delete_confirm = {
            "activity_id": self.activity_id,
            "expected_name": self.activity_name,
            "expected_archived_at": self.archived_at,
            "expected_revision": self.published_revision,
            "expected_draft_revision": self.draft_generation,
        }

    def cancel_delete(self) -> None:
        self.delete_confirm = None

    def confirm_delete(self) -> None:
        frozen = self.delete_confirm
        if not frozen:
            return
        self.delete_confirm = None
        target = str(frozen["activity_id"])
        self.queue = [
            op for op in self.queue
            if not (op.kind == "autosave" and op.activity_id == target)
        ]
        self.enqueue(
            Op(
                kind="delete-archived",
                activity_id=target,
                edit_sequence=self.edit_sequence,
                payload={
                    "activity_id": target,
                    "expected_revision": frozen["expected_revision"],
                    "expected_draft_revision": frozen["expected_draft_revision"],
                    "expected_archived_at": frozen["expected_archived_at"],
                    "expected_name": frozen["expected_name"],
                },
            )
        )

    def unarchive(self) -> None:
        self.delete_confirm = None
        self.enqueue(
            Op(
                kind="unarchive",
                activity_id=self.activity_id,
                edit_sequence=self.edit_sequence,
                payload={"activity_id": self.activity_id},
            )
        )
