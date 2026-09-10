# Archived activity permanent deletion

Post-v0.1.0 candidate. Owner product confirmation: archived-only
permanent delete (not Trash), after a confirmation that names the exact
activity and warns that its checkpoints, history, links, and draft are
removed. Cancel is a no-op. This document freezes the internal store
API from existing `breadcrumb-store` conventions **before**
implementation.

Not a public `bin/breadcrumb` operation. Not bulk delete. Not a new
schema version. Not unarchive. Not automatic expiration.

## Problem

Archive hides an activity without erasing it. Users still need a way to
remove a finished activity they no longer want. Silent overwrite,
Trash, bulk delete, and a public agent delete were rejected. The
existing SQLite CAS, draft-generation tombstones, and UI scheduler
must keep protecting concurrent draft/publication.

## Internal store command

`bin/breadcrumb-store delete-archived-activity`

Same process, JSON stdin or argv JSON, `BEGIN IMMEDIATE`, user-only
DB permissions, and JSON stdout receipts as `archive-activity` /
`save-draft` / `publish`.

### Request

Every field is required. The UI freezes these values when the user
opens confirmation, not when the write is later dequeued.

| Field | Rule | Existing convention |
|---|---|---|
| `activity_id` | Canonical UUID of the target | `require_activity_id` |
| `expected_revision` | Current published checkpoint revision, `0` if none | `publish` CAS |
| `expected_draft_revision` | Durable per-activity draft generation, including a discard tombstone; `0` if no drafts row | `save-draft` / `discard-draft` |
| `expected_archived_at` | Exact `archived_at` timestamp observed at confirm (`…Z`) | activity metadata |
| `expected_name` | Exact activity name shown in the confirmation | activity metadata |

No `force`, no list of ids, no `include_archived`, no public envelope.

### Transaction checks (in order)

1. Unknown `activity_id` → `validation` / “Unknown activity.” No write.
2. `archived_at` is null → `validation` / “Only archived activities can be deleted.” No write.
3. `archived_at != expected_archived_at` → `stale_revision` (concurrent unarchive/re-archive). Extra: `current_archived_at`, `expected_archived_at`.
4. `name != expected_name` → `stale_revision` (renamed after confirm). Extra: `current_name`, `expected_name`.
5. Latest checkpoint revision ≠ `expected_revision` → `stale_revision` (concurrent publication). Extra: `current_revision`, `expected_revision`.
6. `current_draft_revision` ≠ `expected_draft_revision` → `stale_revision` (concurrent draft save/discard). Extra: `current_draft_revision`, `expected_draft_revision`.

`current_draft_revision` is `0` when no `drafts` row exists, otherwise
`drafts.revision` (live draft or tombstone).

### Atomic delete

On success, one transaction deletes only this activity’s rows:

1. `checkpoint_links` for its checkpoints
2. `checkpoints`
3. `draft_links`
4. `drafts` (live draft and generation tombstone)
5. `activities`

Then, if `prefs.selected_activity_id` was the deleted id, retarget it
with the same fallback as `load_activity(None)` over remaining rows
(`include_archived=True`, `created_at DESC, id DESC`). If none remain,
delete that pref key (empty `set_pref` is not allowed). Other
activities, their checkpoints/drafts/links, view prefs, and unrelated
selected-id values must not change.

Foreign keys are not `ON DELETE CASCADE` for checkpoints/drafts; the
command must delete children before the parent. A mid-statement abort
rolls back the whole transaction.

### Success receipt

```json
{
  "ok": true,
  "deleted_activity_id": "<uuid>",
  "selected_activity_id": "<uuid or null>"
}
```

`selected_activity_id` is the pref after fallback, or `null` when the
store is empty. The UI then `get`s that id (or empty `get`) with the
current `include_archived` flag. No activity row is returned because
it is gone.

### Errors

Same codes/exits as other store commands: `validation` 3,
`stale_revision` 4, `permission` 5, `io` 6. Failed delete does not
remove the activity, checkpoints, links, or draft.

After a successful delete, `save-draft` / `publish` with that id are
`validation` “Unknown activity.” `get` with a missing id still reports
the existing empty snapshot plus remaining activities; it does not
recreate the row. A queued or in-flight autosave must not recreate the
activity.

## UI contract

- Delete control is visible only for the selected archived activity
  (Expanded, next to existing archive controls). Compact has no delete.
- Confirmation names `expected_name` and warns that checkpoints,
  history, links, and the draft are permanently removed.
- Cancel clears the confirmation and sends no store command.
- Switching activity, toggling archived, create, or archive clears a
  pending confirmation without deleting.
- Confirm enqueues `delete-archived-activity` with the frozen payload.
  `sendOp` must not rebind CAS fields from live editor state.
- Last remaining activity → existing empty state.
- Store error surfaces `lastError` and leaves the draft/editor.

## Public command

`bin/breadcrumb` stays `list` / `read` / `publish`.
`delete-archived-activity`, `delete`, and related keys are invalid
requests. Agents must not call `breadcrumb-store` for deletion.

## Tests

- Store: actual `breadcrumb-store` process tests for archived-only
  delete, child/parent cascade, neighbor isolation, stale
  revision/draft/archive/name, last-activity empty pref, failed-delete
  rollback, and post-delete autosave non-resurrection.
- Scheduler: `tests/draft_session.py` cancellation, target switch,
  last activity, stale confirmation, failed delete preserving draft,
  queued autosave after delete.
- QML: source contracts in `tests/test_plugin_contract.py`.
- Native qs harness is not extended in this candidate (96-step
  Compact/Expanded component test remains the prior v0.1.0 evidence).

## Limits

- No Trash / undo / unarchive command.
- No bulk delete.
- No public delete.
- Isolated native/component run of the new confirmation overlay is a
  remaining gap unless separately executed on the-cave with disposable
  HOME/XDG.
- Live plugin `9cdf2a7` is untouched.

## AI credit

Implemented with AI assistance (Hermes). Owner approved the product
behavior (“yea delete perm”), not a code-security audit.
