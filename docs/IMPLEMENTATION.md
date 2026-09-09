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

## Storage (additive, compatibility)

- Python 3 stdlib `sqlite3` only. Store **schema version remains 1**.
- Existing v1 files open in place. `CREATE TABLE IF NOT EXISTS` adds `drafts` and `draft_links`. No rewrite of checkpoints or activities.
- Default directory, `breadcrumb.sqlite` permissions, `PRAGMA journal_mode=DELETE`, `PRAGMA synchronous=FULL`, `BEGIN IMMEDIATE`, and `busy_timeout` are unchanged.
- Drafts are **not** checkpoints. Autosave never `INSERT`s into `checkpoints` / history.

### Explicit draft model

One draft row per activity:

| Field | Role |
|---|---|
| `activity_id` | Stable activity UUID (PK). |
| `revision` | Draft version, starts at 1. CAS token. Distinct from published checkpoint `revision`. |
| `base_revision` | Published checkpoint revision the user last acknowledged when this draft began or was last resolved. Autosave does **not** rebase this after an external publish. |
| summary / next_step / context / state / author / updated_at / links | Editor payload. Incomplete drafts are allowed (empty summary/next_step). Length and NUL rules still apply. Link *targets* are stored for recovery; publish still validates links. |

`drafts.revision` is the only draft concurrency token. Published `expected_revision` remains the only checkpoint CAS token.

### Transaction / concurrency contracts

Every mutating command (`save-draft`, `discard-draft`, `publish`, `restore`, …) loads the latest on-disk row **inside** `BEGIN IMMEDIATE`, checks the caller’s expected token, then writes or rolls back. Two store processes on the same file serialize at SQLite, not at a process-wide lock.

| Operation | Freshness check | Success | Failure |
|---|---|---|---|
| `save-draft` | `expected_draft_revision` equals current draft revision, or `0` if none | Upsert revision N+1, replace links | `stale_revision` with `current_draft_revision`; prior draft bytes unchanged |
| `discard-draft` | Same CAS; missing draft + expected `0` is idempotent success | Delete draft + links | Stale: newer draft kept |
| `publish` | Published `expected_revision` CAS. Optional `consume_draft_revision`: delete the draft only when that token still matches. Omit it for the external/test-seam writer so a newer publication keeps the local draft. | Append checkpoint; consume matching draft in the same transaction | Stale: published row and draft both unchanged |
| `get` | Read | Snapshot includes `current` (published) and `draft` (or `null`) | Read errors do not return empty stand-ins for valid rows |

Delayed writers: a `save-draft` whose `expected_draft_revision` no longer matches (discarded, published-and-cleared, or a newer draft) is rejected and must not insert a row. That is the store-side guard against resurrecting discarded/published drafts and against overwriting a newer draft.

External publications in this slice use the existing `publish` command as an **internal test seam**. The public agent CLI remains issue #6.

## Store API additions

`bin/breadcrumb-store` remains the UI persistence seam.

| Command | Payload | Result |
|---|---|---|
| `save-draft` | `{activity_id, expected_draft_revision, base_revision, summary, next_step?, context?, state, author, links?}` | `{draft}` with `revision`, `base_revision`, fields, `updated_at`, `links`. No history entry. |
| `discard-draft` | `{activity_id, expected_draft_revision}` | `{draft: null}` |
| `get` | unchanged | Adds `draft` (`null` or payload). `revision` is still the published checkpoint revision. |
| `publish` | existing fields plus optional `consume_draft_revision` | On success, matching draft is consumed. Omitted consume leaves the draft (external seam). On `stale_revision`, draft is untouched and `current_revision` is returned. |

## UI contracts

- Compact always renders the **published** checkpoint (`current.*`), never editor/draft text. A visible “Unsaved draft” indicator appears when `draft` exists.
- Expanded hydrates the editor from `draft` when present, else from `current`. Collapse keeps the draft on disk and shows published text in Compact.
- Panel recreate / close / reopen: `get` recovers the draft into the editor. History count is unchanged.
- Same-instance `refresh()` must not clobber unacknowledged editor keystrokes (`dirty` since last successful `save-draft`).
- Programmatic hydration (`copyCurrentToEditor` / applying a recovered draft) sets a hydrating guard so `onTextChanged` / recovered text cannot schedule autosave.
- Autosave is scheduled only from genuine user edits (`onTextEdited` / explicit dirty). Acknowledgment is honest: “Draft saved” only after a matching `save-draft` ok. In-flight shows “Saving draft…”. Failure is `lastError` and never blanks the editor.
- One `Process` is single-flight. Coalesce queued `save-draft`. Capture `activity_id`, `expected_draft_revision`, and a client generation at send time. Ignore or compensate results whose generation/activity no longer match (wrong-activity async, discard/publish while in flight).
- Activity switch and create: persist the current draft first. If `save-draft` fails, **do not switch/create**; keep editor text, show the error, resync the compact picker. This replaces the #4 in-memory Save/Discard/Cancel switch prompt. Discard is an explicit Expanded action. Restore while a draft exists is still refused so history restore cannot clobber unpublished text.
- Stale **Save checkpoint**: keep the draft in the editor, load the newer published `current` for display, show a conflict prompt. Resolution is deliberate against the **observed** current revision: Save draft as a new checkpoint (`expected_revision` = the revision now shown), Load published (discard draft, hydrate from `current`), or Keep editing. The UI never silently retries publish with an updated expected revision.

## Out of scope

Public agent CLI (#6), glance polish / Button.enabled host gap (#7), live install/release (#8).

## Verification

Recorded after RED→GREEN. Python tests are not native Omarchy evidence.

### Source (Python)

RED, first missing command:

```
cd tests && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest test_drafts.TestDrafts.test_save_draft_persists_without_publishing_history -v
```

Failed: `AssertionError: 2 != 0` (`save-draft` unknown). Later slices similarly started from missing `discard-draft` (exit 2) and from `publish` wiping an unrelated draft.

GREEN, full suite from the repository root:

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
python3 -m py_compile bin/breadcrumb-store tests/*.py
git diff --check
```

43 tests OK (11.308s), including draft CAS, discard/publish non-resurrection, concurrent external publish + save-draft, v1 additive drafts table, permission-error prior-byte preserve, and source contracts for autosave/conflict/native harness strings.

### Native (isolated component, the-cave)

Not live desktop acceptance. Unique disposable `HOME`/`XDG`, `QT_QPA_PLATFORM=offscreen`, no Wayland, no `shell.json` mutation, no plugin enable, live `qs` pid unchanged.

```
ARCHIVE=<git-archive-or-working-tree-tar> \
CANDIDATE_SHA=<commit> \
EVIDENCE_DIR=/tmp/breadcrumb-evidence-XXXX \
HARNESS_SRC=tests/native/harness \
  ./tests/native/run-isolated.sh
```

Pre-commit working-tree run: `validate_rc=0`, `qs_rc=0`, `ui_ok=true`, `HARNESS_OK`, `classification=component-test-not-full-host-integration`. Compact showed published lantern checkpoint with `hasDraft`; recreate recovered `Durable lantern draft after close` without bumping `draftRevision`; store-seam `publish` set `conflictPrompt` while keeping the draft; resolution published revision 5 against observed revision 4. Live `shell.json` sha unchanged; live plugin dir still had no `tbassss.breadcrumb`.

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
