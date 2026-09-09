# Implementation notes for issue #5

Crash-safe per-activity draft autosave and explicit stale-save resolution.
Not a release, not installed, not a public agent CLI (issue #6).

Technical decisions below were recorded before production code.

## Supported Omarchy APIs

Unchanged from issues #3 and #4, inspected read-only on the-cave:

- Plugin contract: `manifest.json` at plugin root, `schemaVersion: 1`, `kinds` + `entryPoints`, no `omarchy.*` id, no symlinks.
- Bar widget host: `qs.Ui.Panel` + `BarIconButton` + `KeyboardPanel` + `PanelKeyCatcher`, theme via `qs.Commons`.
- Subprocess: `Quickshell.Io.Process` with `command` as a string list; JSON payload is an argv element.
- Open links: `Quickshell.execDetached(open_argv)` after `validate-link`.
- Toolchain on the-cave: `/usr/bin/python3` 3.14, `/usr/bin/qs` Quickshell 0.3.1, Qt 6.11.2, `omarchy plugin validate`.
- Known full-host `qs.Ui.Button.enabled` mismatch remains issue #7. Package Button is not patched. Live host acceptance is not claimed.

## Repair (review blockers on 52541e3)

Recorded before production edits. Three identities stay distinct for the whole slice:

| Identity | Owner | Advances when |
|---|---|---|
| Published checkpoint `revision` | `checkpoints` row | Successful `publish` / `restore` |
| Durable draft **generation** | Per-activity head, including empty/tombstone | Every successful `save-draft`, `discard-draft`, and matching consume |
| Editor **edit sequence** | UI session | Genuine user keystroke / dirty |
| Immutable request snapshot | One queued/in-flight op | Captured at enqueue for payload + activity + edit sequence; CAS tokens bound at send |

Ordinary draft save CAS-es the **acknowledged draft base**. Only an explicit reviewed resolution may advance that base, and that path itself CAS-es the **observed** published revision. Close/reopen and Keep editing must not adopt `root.revision` after refresh.

Draft delete/consume must not physically remove the head row. Generation never restarts at 1. Stale discard/consume against an old generation cannot ABA-delete a newer live draft. Existing v1 files gain an additive `live` column; live payload bytes are not rewritten on migrate.

UI store mutations go through an explicit FIFO scheduler. Unsent autosaves for the **same activity** may coalesce. Explicit Save, discard, and navigation are never silently dropped. Acks match the exact saved edit sequence. Newer editor text is preserved. Navigation waits for persist or is deferred with visible state. Stale responses never clear/overwrite the editor and never issue a compensating discard.

## Storage (additive, compatibility)

- Python 3 stdlib `sqlite3` only. Store **schema version remains 1**.
- Existing v1 files open in place. `CREATE TABLE IF NOT EXISTS` adds `drafts` and `draft_links`. Existing draft tables get `live INTEGER NOT NULL DEFAULT 1` if missing. No rewrite of checkpoints, activities, or live draft payloads.
- Default directory, `breadcrumb.sqlite` permissions, `PRAGMA journal_mode=DELETE`, `PRAGMA synchronous=FULL`, `BEGIN IMMEDIATE`, and `busy_timeout` are unchanged.
- Drafts are **not** checkpoints. Autosave never `INSERT`s into `checkpoints` / history.

### Explicit draft model

One **head row** per activity, retained through empty/tombstone states:

| Field | Role |
|---|---|
| `activity_id` | Stable activity UUID (PK). |
| `revision` | Monotonic **generation** (CAS token). Starts at 1 on first save. Discard/consume increment it and leave a tombstone (`live=0`). Never reset to 0/1 while the row exists. Distinct from published checkpoint `revision`. |
| `live` | `1` = payload is an outstanding draft. `0` = empty/tombstone. `get` reports `draft: null` for tombstones but still returns `draft_generation`. |
| `base_revision` | Published checkpoint revision last **acknowledged** for this live draft. Ordinary `save-draft` cannot change it. Explicit `acknowledge_base` may advance it only when `observed_revision` CAS-matches the current published revision. |
| summary / next_step / context / state / author / updated_at / links | Editor payload while `live=1`. Cleared on tombstone; generation is kept. Incomplete drafts are allowed. Link *targets* are stored for recovery; publish still validates links. |

Missing row (legacy never-drafted activity) is generation `0`. After the first draft, the row remains. `drafts.revision` is the only draft concurrency token. Published `expected_revision` remains the only checkpoint CAS token.

### Transaction / concurrency contracts

Every mutating command (`save-draft`, `discard-draft`, `publish`, `restore`, …) loads the latest on-disk row **inside** `BEGIN IMMEDIATE`, checks the caller’s expected token, then writes or rolls back. Two store processes on the same file serialize at SQLite, not at a process-wide lock.

| Operation | Freshness check | Success | Failure |
|---|---|---|---|
| `save-draft` | `expected_draft_revision` equals current generation (0 only if no row). Ordinary save: if `live=1`, `base_revision` must equal stored base. Optional `acknowledge_base` + `observed_revision`: `observed_revision` must equal latest published revision; then base becomes that observed revision. | Upsert generation N+1, `live=1`, replace links | `stale_revision` with `current_draft_revision` and `current_base_revision` when relevant; prior bytes unchanged |
| `discard-draft` | Same generation CAS. Missing row + expected `0` is idempotent success. Tombstone + matching generation is idempotent success. | Increment generation, `live=0`, clear payload, drop links. Row remains. | Stale: live or tombstone head unchanged |
| `publish` | Published `expected_revision` CAS. Optional `consume_draft_revision`: **required match** when present — mismatch fails the whole publish. Omit consume for the external/test-seam writer. | Append checkpoint; matching consume tombstones (does not DELETE) in the same transaction | Stale: published row and draft head both unchanged |
| `get` | Read | `current` (published), `draft` (live payload or `null`), `draft_generation` (0 if no row) | Read errors do not return empty stand-ins for valid rows |

Delayed writers: a `save-draft` / `discard-draft` / consume whose generation no longer matches is rejected and must not insert, delete, or tombstone a newer head. That is the store-side guard against ABA after discard/recreate and against resurrecting discarded drafts.

External publications in this slice use the existing `publish` command as an **internal test seam**. The public agent CLI remains issue #6.

## Store API additions

`bin/breadcrumb-store` remains the UI persistence seam.

| Command | Payload | Result |
|---|---|---|
| `save-draft` | `{activity_id, expected_draft_revision, base_revision, summary, next_step?, context?, state, author, links?, acknowledge_base?, observed_revision?}` | `{draft}` with `revision` (generation), `base_revision`, fields, `updated_at`, `links`. No history entry. |
| `discard-draft` | `{activity_id, expected_draft_revision}` | `{draft: null, draft_generation}` |
| `get` | unchanged | Adds `draft` (`null` or live payload) and `draft_generation`. `revision` is still the published checkpoint revision. |
| `publish` | existing fields plus optional `consume_draft_revision` | On success, matching consume tombstones the head. Omitted consume leaves a live draft. Consume mismatch is `stale_revision` and does not append. |

Ordinary UI Save checkpoint sends `expected_revision` = acknowledged `draft.base_revision` (not the refreshed published revision). Explicit “Save draft as checkpoint” sends `expected_revision` = the observed revision captured when the conflict was shown.

## UI contracts

Identities: `revision` (published), `draftRevision` (durable generation, including tombstone), `editSequence` (editor), `inFlight` snapshot (request id, activity, edit sequence, generation, payload).

- Compact always renders the **published** checkpoint (`current.*`), never editor/draft text. A visible “Unsaved draft” indicator appears when a **live** draft exists.
- Expanded hydrates the editor from live `draft` when present, else from `current`. Collapse keeps the draft on disk and shows published text in Compact.
- Panel recreate / close / reopen: `get` recovers a live draft into the editor and restores `draftBaseRevision` from `draft.base_revision`, not from refreshed `current.revision`. History count is unchanged. Tombstone generation is adopted so the next save CAS-es the head.
- Same-instance `refresh()` must not clobber unacknowledged editor keystrokes (`editSequence` since last acked save).
- Programmatic hydration sets a hydrating guard so recovered text cannot schedule autosave.
- Autosave is scheduled only from genuine user edits. Acknowledgment is honest: “Draft saved” only when the acked snapshot’s `editSequence` still matches the editor. In-flight shows “Saving draft…”. Failure is `lastError` and never blanks the editor.
- Store mutations serialize on an explicit FIFO scheduler (`enqueueOp` / `pumpQueue`). Coalesce **only** unsent autosaves for the same activity. Never silently drop explicit Save, discard, or navigation. CAS tokens are bound at send. Stale/wrong-activity responses are ignored for editor state and **must not** compensating-discard.
- Activity switch and create: persist the current draft first. If a save is in flight or the editor moved past the in-flight sequence, **defer** navigation with visible “Saving draft…” and keep the picker on the current activity until the exact current sequence is persisted — or show the error and do not switch. Discard is an explicit Expanded action. Restore while a live draft exists is still refused.
- Stale **Save checkpoint**: keep the draft in the editor, load the newer published `current` for display, capture `observedRevision`, show a conflict prompt. Ordinary Save continues to CAS `draftBaseRevision`. Keep editing does not advance base. Only “Save draft as checkpoint” publishes against `observedRevision` (itself a CAS). Load published discards against the current generation. The UI never silently retries ordinary publish with a refreshed expected revision.

## Out of scope

Public agent CLI (#6), glance polish / Button.enabled host gap (#7), live install/release (#8).

## Verification

Recorded after RED→GREEN. Python tests are not native Omarchy evidence.

### Source (Python)

RED, against 52541e327fa8101b566926d71589e04148068270 plus the new tests only:

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

Failed (7): missing `draft_session`; ordinary `save-draft` accepted a rebased `base_revision`; `acknowledge_base` did not CAS observed revision; stale discard/consume after recreate deleted the new draft (`draft_generation` absent); Panel still used `expected_revision: root.revision` and the singleton queue/`discard-draft` compensate path.

GREEN, full suite from the repository root:

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
python3 -m py_compile bin/breadcrumb-store tests/*.py
git diff --check
```

53 tests OK (13.401s), including acknowledged-base CAS, Keep-editing old-base publish conflict, generation tombstones, ABA stale discard/consume, overlapping session scheduler, and source contracts for ordinary Save vs observed resolution.

### Native (isolated component, the-cave)

Not live desktop acceptance. Unique disposable `HOME`/`XDG`, `QT_QPA_PLATFORM=offscreen`, no Wayland, no `shell.json` mutation, no plugin enable, live `qs` pid unchanged.

```
ARCHIVE=<git-archive-or-working-tree-tar> \
CANDIDATE_SHA=<commit> \
EVIDENCE_DIR=/tmp/breadcrumb-evidence-XXXX \
HARNESS_SRC=tests/native/harness \
  ./tests/native/run-isolated.sh
```

Working-tree run: `validate_rc=0`, `qs_rc=0`, `ui_ok=true`, `HARNESS_OK`, `classification=component-test-not-full-host-integration`, finished `step=54`. Recreate after external publish kept draft base 3 vs published 4; ordinary Save and Keep-editing retry both set `conflictPrompt` without overwriting the agent checkpoint; resolution published revision 5 against observed 4. Same-tick autosave+keystrokes+nav recovered `overlap-autosave-nav-v2`; explicit Save behind queued autosave published `explicit-save-behind-autosave`; overlapping discard left `typed-during-discard`. Live `shell.json` sha unchanged (`469bfd9b5c8a29ff3e5e8f45a09a66729eaf6a4e4b42462cf26fc99f4102eaee`); live `qs` pid 1600 unchanged; live plugin dir still had no `tbassss.breadcrumb`.

### Classification

| Check | Kind |
|---|---|
| `unittest discover -s tests` | Source-contract / store process |
| Isolated `tests/native/` on the-cave | Native component (real Panel.qml + qs + Qt offscreen) |
| Full omarchy-shell bar / KeyboardPanel / Button.enabled | **Not run.** Issue #7. |

## Remaining blockers

- Independent persistence/concurrency review (parent-owned; required before merge).
- Public agent CLI is issue #6.
- Glance polish and the known full-host `Button.enabled` mismatch are issue #7. Package Button was not patched.
- Live install, restart, merge, and release remain unapproved.
- This slice is not release-ready.
