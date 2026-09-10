# Archived activity permanent deletion

Post-v0.1.0 candidate. Owner product confirmation: archived-only
permanent delete (not Trash), after a confirmation that names the exact
activity and warns that its checkpoints, history, links, and draft are
removed. Cancel is a no-op. This document freezes the internal store
API from existing `breadcrumb-store` conventions **before**
implementation.

Not a public `bin/breadcrumb` operation. Not bulk delete. Not a new
schema_meta version. Not unarchive. Not automatic expiration.

Additive column `activities.archive_generation INTEGER NOT NULL DEFAULT 0`
is applied crash-safely in the existing `BEGIN IMMEDIATE` `init_schema`
transaction (`CREATE TABLE` for new stores, `ALTER TABLE` when the
column is missing). `schema_meta.version` remains `1`. Missing
`expected_archive_generation` is `validation` and does not delete.

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
| `expected_archive_generation` | Monotonic per-activity archive generation observed at confirm; `0` if never archived | activity metadata, retained across unarchive |
| `expected_name` | Exact activity name shown in the confirmation | activity metadata |

No `force`, no list of ids, no `include_archived`, no public envelope.

### Transaction checks (in order)

1. Unknown `activity_id` → `validation` / “Unknown activity.” No write.
2. `archived_at` is null → `validation` / “Only archived activities can be deleted.” No write.
3. `archived_at != expected_archived_at` → `stale_revision` (concurrent unarchive/re-archive). Extra: `current_archived_at`, `expected_archived_at`.
4. `archive_generation != expected_archive_generation` → `stale_revision` (same-second or clock-rollback unarchive/re-archive). Extra: `current_archive_generation`, `expected_archive_generation`.
5. `name != expected_name` → `stale_revision` (renamed after confirm). Extra: `current_name`, `expected_name`.
6. Latest checkpoint revision ≠ `expected_revision` → `stale_revision` (concurrent publication). Extra: `current_revision`, `expected_revision`.
7. `current_draft_revision` ≠ `expected_draft_revision` → `stale_revision` (concurrent draft save/discard). Extra: `current_draft_revision`, `expected_draft_revision`.

`current_draft_revision` is `0` when no `drafts` row exists, otherwise
`drafts.revision` (live draft or tombstone).

`archive_generation` starts at `0`. Each successful archive of an
active activity increments it by one in the same `UPDATE` that sets
`archived_at`. Already-archived archive is still a no-op (generation
unchanged). Unarchive clears `archived_at` and **retains** generation.
Wall-clock rollback and same-second re-archive therefore cannot reuse
a prior delete consent identity. Migrated rows without the column
receive `0`; after one unarchive/re-archive cycle their generation is
`1` and a generation-`0` confirmation is `stale_revision`.

Rolling a store binary back to a build that does not check
`expected_archive_generation` reintroduces same-second `archived_at`
ABA. New public `list`/`read` objects still omit `archive_generation`.

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
  revision/draft/archive/name/archive-generation, same-second and
  clock-rollback unarchive/re-archive ABA, second-instance current
  confirmation, concurrent archive/delete/unarchive serial outcomes,
  additive `archive_generation` migration, last-activity empty pref,
  failed-delete rollback, and post-delete autosave non-resurrection.
- Scheduler: `tests/draft_session.py` cancellation, target switch,
  last activity, stale confirmation, failed delete preserving draft,
  queued autosave after delete.
- QML: source contracts in `tests/test_plugin_contract.py`.
- Native: `tests/native/run-delete-isolated.sh` +
  `tests/native/harness/delete-shell.qml` on the-cave (isolated
  HOME/XDG, packaged controls, stub KeyboardPanel/host Panel). Covers
  Compact-not-delete, collapse cancel, no Compact execution, no
  confirm resurrection, keyboard default Cancel, named warning, Cancel
  no-op, stale publish, same-second unarchive/re-archive retained
  confirmation, selection fallback, last-entity empty. The
  prior 96-step Compact/Expanded harness remains v0.1.0 evidence.

## Limits

- No Trash / undo after permanent delete. Unarchive is a separate
  reversible command documented in [UNARCHIVE_ACTIVITY.md](UNARCHIVE_ACTIVITY.md).
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
- Rolling a store binary back to a build that does not check
  `expected_archive_generation` reintroduces same-second `archived_at`
  ABA. `schema_meta.version` stays `1` so that rollback can still open
  the database.

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

## Archive-generation ABA repair

Parent unarchive candidate `25e627239b97d1ab53751fe305a2d1dd02d68db4`
passed review except same-second `archived_at` ABA: an old delete
payload still deleted after unarchive/re-archive in the same second.
This pass adds monotonic `archive_generation` retained across
unarchive, required on delete confirmation, additive `schema_meta`
version-1 migration.

| Item | Value |
|---|---|
| Parent candidate | `25e627239b97d1ab53751fe305a2d1dd02d68db4` |
| Python RED | old delete bytes after same-second cycle returned `ok:true` |
| Python GREEN | 100 tests OK (`unittest discover -s tests`) |
| Native delete GREEN | `/tmp/breadcrumb-delete-gen-UgdH`; step 33; `staleCycleRejected=true`; frozen generation 1; current confirmation after Reload deleted |
| Native unarchive GREEN | `/tmp/breadcrumb-unarchive-gen-9r91`; step 18; selection/revision/draft preserved |
| Workdir `Panel.qml` | `df45cc350a7ffa5490246919361886c98b1ab3b7d1af47289c49826b4febdc99` |
| Workdir `bin/breadcrumb-store` | `b0fc0b77c82f71fb85644ce05a30081ebff8933a6d52bae3c43419c75ef80504` |
| Workdir `bin/breadcrumb` | `e39e8b17c4717ee4aa49511bfce4122b77ec32f65ca571a671cf7f61245711af` |
| Working-tree tar | `556504df322aa155cdcf46e056f3d7207830ba9793777cf835aed4b9bd307d8e` |
| Live plugin / shell.json / qs pid | unchanged (584804 / `2bc54c753a5a529b02409e17c093640558341597aa38721cfd55eb97b168360f`) |

Local-only. No live install, restart, push, merge, or version change.

## AI credit

Implemented with AI assistance (Hermes). Owner approved the product
behavior (“yea delete perm”), not a code-security audit.
