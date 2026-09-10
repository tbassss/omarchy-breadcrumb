# Unarchive activity

Post-v0.1.0 candidate. Not a new GitHub release, directory listing, or
live install. Public `bin/breadcrumb` remains `list` / `read` /
`publish` only.

Owner asked to restore an archived activity to the active list. That is
reversible and non-destructive. It is not history Restore and not
permanent Delete.

## Behavior

- Expanded archived activity shows **Unarchive**. One click. No
  confirmation.
- The same stable activity returns to the active list. Selection,
  current checkpoint, history, links, and any saved or in-memory draft
  stay. Unarchive does not append a checkpoint.
- Compact does not show Unarchive or Delete.
- Delete remains archived-only. After unarchive, Delete is hidden.
- Pending delete confirmation is cleared on Unarchive. A later delete
  with the old archived CAS tokens is rejected and does not mutate.
- Concurrent delete/unarchive cannot resurrect a deleted row or write
  the wrong activity. Unknown/deleted id is `validation`. Failed
  unarchive rolls back.
- Already-active unarchive is idempotent (`archived_at` stays null).

## Store

Internal `breadcrumb-store` command `unarchive-activity`, same shape as
`archive-activity`: `{ "activity_id": "<uuid>" }`.

- `BEGIN IMMEDIATE`
- Unknown activity → `validation`
- `archived_at IS NULL` → success, no write
- else `UPDATE activities SET archived_at = NULL WHERE id = ?`
- Checkpoints, drafts, links, and `selected_activity_id` are untouched
- Injected UPDATE fault → `io`, row stays archived

No schema migration. Public command rejects `unarchive` /
`unarchive-activity`.

## UI

- `unarchiveActivity(id)` clears `deleteConfirm` then runs
  `unarchive-activity`.
- `qs.Ui.Button` has no `enabled`. Clicks are guarded; keyboard uses
  `focusable`. Packaged `BarIconButton` still requires `iconComponent`.
- Keyboard: Unarchive is in `keyboardTargets` while the archived
  activity is expanded.

## Verification

- Python: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`
  — **94 tests, OK** (22.871s). Includes `tests/test_unarchive.py`,
  scheduler tests in `tests/test_draft_session.py`, plugin source
  contracts, public-command rejection of `unarchive` /
  `unarchive-activity`.
- `python3 -m py_compile bin/breadcrumb-store bin/breadcrumb tests/*.py`
  — OK. `git diff --check` — OK. Markdown links — OK.
- Native (the-cave, 2026-09-09T20:14:16-07:00): isolated HOME/XDG,
  `QT_QPA_PLATFORM=offscreen`, packaged qs.Ui overlay, stub
  KeyboardPanel/host Panel. `LIVE_PLUGIN_DIR` pointed at empty
  disposable `/tmp/breadcrumb-live-plugin-absent-mPw4` (absence guard
  is not proof the live plugin is missing). Independent live hashes
  taken before/after.
  - `omarchy plugin validate` isolated copy: `validate_rc=0`
  - `qs_rc=0`, harness `ui_ok=true`, step 18, `HARNESS_OK`
  - Results file absent; runner recovered structured payload from
    stdout (`recovered_ui_results_from_stdout bytes 4385`) and applied
    the same asserts.
  - compactHadUnarchive=false, compactHadDelete=false,
    unarchivePreservedSelection/Revision/Draft=true,
    deleteHiddenAfterUnarchive=true, confirmClearedOnUnarchive=true,
    keyboardUnarchivePresent/Activated=true, neighborKept=true
  - SQLite after run: Gone Trail Map `archived_at` null, revision 1
    checkpoint unchanged, durable draft row still live, Keep neighbor
    intact, selected_activity_id still Gone.
  - `live_plugin_shell_pid_unchanged=yes` (live qs pid 584804,
    shell.json `2bc54c753a5a529b02409e17c093640558341597aa38721cfd55eb97b168360f`)
  - Packaged overlay: `bariconbutton_iconComponent=1`,
    `button_declares_enabled=0`
  - Classification: component test, not live bar / WlrLayershell.
  - Evidence dir on cave: `/tmp/breadcrumb-unarchive-evidence-v1PJ`
    (temporary; do not treat as durable repo storage).

Runtime bytes exercised on cave (workdir plugin, not live install):

| File | SHA-256 |
|---|---|
| Panel.qml | `ff32ce6276341baf3be0c32c59a627c40658c34267ad3982a63e6a1ffa77efe3` |
| bin/breadcrumb-store | `feffddee96bbf89e5b9fe7a63a0cf1e144342988ae08cfb7fcb64e6088ed704e` |

Working-tree tar used for that run:
`dbddc886c6b55cd09533a77655e6a94abf3e8ba5b712ae0be5c4edff67105f18`.
Commit SHA is the candidate identity after this documentation land.

## Limits

- No confirmation (intentional; reversible).
- No public unarchive.
- Native coverage is a component test (packaged child controls + real
  Panel.qml + offscreen qs). Not live bar, WlrLayershell, Escape,
  popup switching, monitor placement, or theme readability.
- Unarchive does not toggle `showArchived`. If that filter is on, the
  now-active activity still appears because `include_archived` lists
  active rows first.
- This candidate does not install, restart the shell, push, merge, or
  change the v0.1.0 version.

AI assistance was used to implement this slice. Owner usability
approval is not a claim that the owner audited code security.
