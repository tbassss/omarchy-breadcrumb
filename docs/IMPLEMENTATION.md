# Implementation notes for issue #4

Named activities and dated checkpoint history. Not a release, not installed,
not disk-draft recovery, not a public agent CLI.

## Supported Omarchy APIs

Unchanged from issue #3, inspected read-only on the-cave:

- Plugin contract: `manifest.json` at plugin root, `schemaVersion: 1`, `kinds` + `entryPoints`, no `omarchy.*` id, no symlinks.
- Bar widget host: `qs.Ui.Panel` + `BarIconButton` + `KeyboardPanel` + `PanelKeyCatcher`, theme via `qs.Commons`.
- Subprocess: `Quickshell.Io.Process` with `command` as a string list; JSON payload is an argv element.
- Open links: `Quickshell.execDetached(open_argv)` after `validate-link`.
- Toolchain on the-cave: `/usr/bin/python3` 3.14, `/usr/bin/qs` Quickshell 0.3.1, Qt 6.11.2, `omarchy plugin validate`.

## Storage (current schema, additive)

- Python 3 stdlib `sqlite3` only. Schema version remains **1**.
- Default directory: `$XDG_DATA_HOME/breadcrumb` or `~/.local/share/breadcrumb` (0700). Override: `BREADCRUMB_DATA_DIR`.
- Database `breadcrumb.sqlite` (0600). Rollback journal (`PRAGMA journal_mode=DELETE`) and `PRAGMA synchronous=FULL`.
- Existing v1 files open in place. `activities.archived_at` is added with `ALTER TABLE` when missing. No new tables.
- Activity identity is the UUID. Rename does not change `id`. Archive sets `archived_at` and does not delete rows.
- Current checkpoint remains `MAX(revision)` per activity. History is the same append-only `checkpoints` table, newest first.
- Selected activity is `prefs.selected_activity_id`. Publication and restore use `BEGIN IMMEDIATE` plus `expected_revision` CAS.

## Minimal store API

`bin/breadcrumb-store` remains the UI persistence seam, not the public agent command from issue #6.

| Command | Payload | Result |
|---|---|---|
| `ensure-activity` | `{name}` | First-slice bootstrap. Returns the existing first row if any. Does **not** mint additional IDs. |
| `create-activity` | `{name}` | Always inserts a new UUID, selects it, returns `{activity}` including `archived_at`. |
| `list-activities` | `{include_archived?}` | `{activities, selected_activity_id}`. Active first, then archived, insertion order. |
| `rename-activity` | `{activity_id, name}` | Same `id`. Empty names rejected. |
| `archive-activity` | `{activity_id}` | Sets `archived_at` once. Idempotent. Not deletion. |
| `get` | `{activity_id?, include_archived?}` | Snapshot plus `activities` and first history page (`limit` 20). Passing `activity_id` persists selection. |
| `history` | `{activity_id, limit?, before_revision?}` | `{entries, has_more, next_before_revision}`. `limit` 1–50, default 20. Newest first. No expiry. |
| `publish` | issue #3 shape | Unchanged CAS append. |
| `restore` | `{activity_id, checkpoint_id, expected_revision}` | Copies the historical row (including links) as a **new** id/revision/`saved_at`. Never `UPDATE`s old checkpoints. Stale expected revision fails without writing. |
| `set-view` / `validate-link` | issue #3 | Unchanged. |

`activity` is `{id, name, created_at, archived_at}`. History entries use the existing checkpoint payload.

## Switching and in-memory edits

Chosen behavior: **explicit Save / Discard / Cancel**. There is no per-activity in-memory draft map and no disk draft persistence (issue #5).

- Compact and Expanded share one selected activity and one editor.
- If `dirty` is true, `switchActivity` does not call `get`. It shows the prompt and keeps the current activity and editor text.
- Save publishes with CAS, then switches. Discard clears dirty and switches. Cancel leaves the current activity.
- Restore while dirty is refused with an error; it does not clobber the editor.
- Same-instance `refresh()` still preserves a genuine dirty draft (issue #3). Panel recreate hydrates from the saved checkpoint only.

## Native UI

- Compact: `activityPicker` dropdown of the shared activity list, published glance, long names elide.
- Expanded: activity sidebar (create / rename / archive / show archived) plus the shared editor and dated history with Restore / Older.
- Empty active lists and empty archived lists have honest copy. Archived current activities remain readable.

## Out of scope (#5–#8)

Disk draft recovery, public agent CLI, glance polish, live install/release.

## Verification

Python: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v` — 28 tests.

Store RED→GREEN (exact missing-command failures unless noted):

| Check | RED | GREEN |
|---|---|---|
| `create-activity` distinct stable IDs | unknown command rc=2 | PASS |
| isolation + selected activity after restart | `get` did not persist selection | PASS |
| rename keeps id and history | unknown command rc=2 | PASS |
| archive is not deletion; archived remain readable | unknown command rc=2 | PASS |
| dated bounded history pages, isolated | unknown command rc=2 | PASS |
| restore appends a new revision; CAS; no rewrite | unknown command rc=2 | PASS |
| empty/archived lists, 200-char names, v1 `ALTER`, concurrent publish/restore | first-run GREEN (covered by the commands above) | PASS |

Python tests are not native Omarchy evidence.

### Native component test (2026-09-09, the-cave)

Isolated `HOME`/`XDG`, `QT_QPA_PLATFORM=offscreen`, unique `XDG_RUNTIME_DIR`. No Wayland/DISPLAY, no live plugin enable, no `shell.json` mutation, no service restart.

Classification: **component test** — real `Panel.qml` + `/usr/bin/qs` 0.3.1 + Qt 6.11.2 offscreen. Host `qs.Ui` / `qs.Commons` are a minimal facade. `KeyboardPanel` is stubbed to avoid WlrLayershell. Not full omarchy-shell host integration, not a live bar, not a live install.

Working-tree run before commit, evidence dir `/tmp/breadcrumb-issue4-20260909T150618-388067/evidence`, disposable workdir `/tmp/breadcrumb-native-v9bc`.

| Check | Result |
|---|---|
| `omarchy plugin validate` | PASS rc=0 |
| qs offscreen harness | `HARNESS_OK` `ui_ok=true` qs_rc=0, 38 ticks, step 26 |
| #3 save/reopen/recreate/draft preserve | PASS |
| create A then B, separate saves | PASS (`Fictional Garden Path` / `App Project`) |
| switch A/B readback + editor hydrate | PASS |
| dirty switch Save/Discard/Cancel prompt | PASS (`switchPrompt=true`, draft kept, cancel stayed on A) |
| recreate while B selected | PASS (`editSummary===current.summary`, `dirty=false`) |
| archive B and read it back | PASS (`archived_at` set, checkpoint intact) |
| restore first A checkpoint as revision 3 | PASS new id `a17d3946-…`, original id `b0dddda3-…` still present |
| QML runtime errors | none (`qmlErrors: []`, empty stderr) |
| Live `shell.json` hash | unchanged `469bfd9b5c8a29ff3e5e8f45a09a66729eaf6a4e4b42462cf26fc99f4102eaee` |
| Live plugin dir `tbassss.breadcrumb` | absent |
| Live qs pid | unchanged `1600` |

Fictional checkpoints only. Native assertion is `tests/native/harness/shell.qml`, not a source-only substitute.

### Not claimed

- Full host integration (live bar, real `KeyboardPanel` layer-shell, `IpcHandler`)
- Visual desktop acceptance
- Issue #5–#8
- Disk draft recovery after Panel recreate
- Zero undiscovered defects

## Attribution

AI implementation and testing assistance (Hermes Agent / Grok 4.6) wrote the store commands, Panel UI, tests, isolated Cave harness run, and these notes. Owner usability approval is not a claim that the owner audited code security. Independent persistence/security review of the exact candidate is still required.
