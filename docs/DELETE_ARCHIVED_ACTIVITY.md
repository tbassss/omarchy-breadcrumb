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
using `list_activity_rows(include_archived=True)`: remaining active
rows first (`archived_at IS NULL`), then archived, each `rowid ASC`
(insertion order). That is the existing store convention, also used by
`load_activity(None)` after a missing selected id (first remaining
unarchived `rowid ASC`, else first remaining row `rowid ASC`). It is
not `created_at DESC, id DESC`. If none remain, delete that pref key
(empty `set_pref` is not allowed). Other activities, their
checkpoints/drafts/links, view prefs, and unrelated selected-id values
must not change.

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
- Compact must neither display nor execute permanent-delete
  confirmation. Collapse cancels a pending confirmation. Re-expand
  does not resurrect it. `requestDeleteArchived` and
  `confirmDeleteArchived` refuse unless `root.expanded`.
- Confirmation names `expected_name` and warns that checkpoints,
  history, links, and the draft are permanently removed.
- Cancel is the default keyboard target while confirmation is open.
  Return/Space on that default cancels; it does not confirm.
  Request, Cancel, and Confirm are keyboard-reachable in Expanded.
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
- Native: `tests/native/run-delete-isolated.sh` +
  `tests/native/harness/delete-shell.qml` on the-cave (isolated
  HOME/XDG, packaged controls, stub KeyboardPanel/host Panel). Covers
  Compact-not-delete, collapse cancel, no Compact execution, no
  confirm resurrection, keyboard default Cancel, named warning, Cancel
  no-op, stale publish, selection fallback, last-entity empty. The
  prior 96-step Compact/Expanded harness remains v0.1.0 evidence.

## Limits

- No Trash / undo / unarchive command.
- No bulk delete.
- No public delete.
- Native delete coverage is a component test (packaged child controls +
  real Panel.qml + offscreen qs). Not live bar, WlrLayershell, Escape,
  popup switching, monitor placement, or theme readability.
- After a stale delete, `root.revision` stays at the pre-publish value
  until Reload (fail-closed; re-confirm without Reload repeats
  `stale_revision`).
- `createActivity()` itself does not null `deleteConfirm`; clearing
  happens on later `applySnapshot` activity change.
- Live plugin remains untouched by this candidate. No install, restart,
  or publication.

## Independent review history

Candidate `a00bb04dab874568c56dc9f4373d7c5fc5589e29` was independently
reviewed as **BLOCK** for B1 (Compact could show and complete
permanent delete after Expand → confirm → Collapse). Store CAS,
public-CLI exclusion, neighbor isolation, rollback, and
non-resurrection held (17/17 process probes; 84 Python tests). Review
receipt: `/tmp/breadcrumb-delete-review.md`. Residuals Q2, Q5–Q8, Q10
remain non-blocking and were not reopened here. Q1 (fallback wording)
and Q3/Q9 (keyboard + in-repo native harness) are addressed in this
repair. Store/CAS bytes were not changed.

This repair still needs a limited independent closure recheck.
Composer owns final acceptance. No external publication authorized.

## Repair verification (this pass)

Local-only. Isolated Cave component tests. No live plugin install,
restart, or `shell.json` write. `LIVE_PLUGIN_DIR` empty disposable
override scopes the runner absence guard only; real live plugin,
`shell.json`, and qs pid were hashed independently and unchanged.

| Item | Value |
|---|---|
| Parent candidate (BLOCK B1) | `a00bb04dab874568c56dc9f4373d7c5fc5589e29` |
| Parent `git archive` SHA-256 | `39935c232216febb1b56393ccd6e9022231f3dd33e69ece5cf689f0d3500636d` |
| Parent `Panel.qml` | `0858d0378419c6e29fd6817e9980bbcce884ed19defbafe3e9006c5af1a04de5` |
| Store/CAS (`bin/breadcrumb-store`) | `4a228c0766dd485aab14dc5b22f8eeda7e68f1407e481e26ed81487a2fefa655` (unchanged) |
| `bin/breadcrumb` | `21ebfda5833c6a223348d912054d150db515e9f93e22b5a70a26ae8578ec2db9` (unchanged) |
| `Model.js` | `7839f3957043896192ecba5ba29ee99b591dd14b33fd483384e30801ccb60549` (unchanged) |
| Repaired `Panel.qml` | `be4b84ad3a298aa5d96a6ccc3fb3a2e32b9738fdf254bd68a8a363e5dca0948d` |
| Python | 85 tests OK (`unittest discover -s tests`) |
| Native RED (`a00bb04` + new harness) | fail `compact displayed permanent delete confirmation after collapse` |
| Native GREEN | `ok=true` step 33; collapse cancels; Compact neither displays nor executes confirm; no resurrection; keyboard default Cancel; Return cancels; stale publish fail-closed; fallback; last-entity empty |
| Prior 96-step native | `ok=true` step 96; hang 8042ms; viewport containment held |

Cave evidence (disposable, not committed):
`/tmp/breadcrumb-delete-repair/{red,green2,old-native}` and local copy
`/tmp/breadcrumb-delete-repair-evidence/`. Independent review remains
`/tmp/breadcrumb-delete-review.md`.

## AI credit

Implemented with AI assistance (Hermes). Owner approved the product
behavior (“yea delete perm”), not a code-security audit.
