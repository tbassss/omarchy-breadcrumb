# Unarchive activity

Merged on public main; included in local unpublished v0.2.0. Not a new
GitHub release or directory listing until a separate release action.
Public `bin/breadcrumb` remains `list` / `read` / `publish` only.

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
  with the old archived CAS tokens, including
  `expected_archive_generation`, is rejected and does not mutate.
  Same-second or clock-rolled re-archive cannot reuse that consent.
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
- `archive_generation` is retained (not reset)
- Checkpoints, drafts, links, and `selected_activity_id` are untouched
- Injected UPDATE fault → `io`, row stays archived

Additive schema: `activities.archive_generation INTEGER NOT NULL DEFAULT 0`.
`schema_meta.version` stays `1`. New stores create the column; existing
stores `ALTER TABLE` in the same crash-safe `init_schema` transaction.
Each successful archive of an active activity increments generation.
Public `list` / `read` / `publish` omit `archive_generation` and still
reject `unarchive` / `unarchive-activity`.

## UI

- `unarchiveActivity(id)` clears `deleteConfirm` then runs
  `unarchive-activity`.
- `qs.Ui.Button` has no `enabled`. Clicks are guarded; keyboard uses
  `focusable`. Packaged `BarIconButton` still requires `iconComponent`.
- Keyboard: Unarchive is in `keyboardTargets` while the archived
  activity is expanded.

## Verification

- Python: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`
  — **100 tests, OK**. Includes same-second and clock-rollback
  unarchive/re-archive ABA, second-instance current confirmation,
  concurrent archive/delete/unarchive serial outcomes, additive
  `archive_generation` migration, public `list`/`read` omitting
  `archive_generation`, `tests/test_unarchive.py`, scheduler tests,
  plugin source contracts, public-command rejection of `unarchive` /
  `unarchive-activity`.
- `python3 -m py_compile bin/breadcrumb-store bin/breadcrumb tests/*.py`
  — OK. `git diff --check` — OK.
- Native unarchive (the-cave, 2026-09-09T20:43:15-07:00): isolated
  HOME/XDG, `QT_QPA_PLATFORM=offscreen`, packaged qs.Ui overlay, stub
  KeyboardPanel/host Panel. `LIVE_PLUGIN_DIR` pointed at empty
  disposable `/tmp/breadcrumb-live-plugin-absent-F6pm` (absence guard
  is not proof the live plugin is missing). Independent live hashes
  taken before/after.
  - `omarchy plugin validate` isolated copy: `validate_rc=0`
  - `qs_rc=0`, harness `ui_ok=true`, step 18, `HARNESS_OK`
  - Results file absent; runner recovered structured payload from
    stdout (`recovered_ui_results_from_stdout bytes 4370`) and applied
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
  - Evidence dir on cave: `/tmp/breadcrumb-unarchive-gen-9r91`
    (temporary; do not treat as durable repo storage).
- Native delete (the-cave, 2026-09-09T20:42:54-07:00): same isolation.
  `LIVE_PLUGIN_DIR` `/tmp/breadcrumb-live-plugin-absent-Q8xw`.
  `validate_rc=0`, `qs_rc=0`, `ui_ok=true`, step 33, `HARNESS_OK`.
  Results recovered from stdout (`10495` bytes).
  `staleCycleRejected=true`, `frozenArchiveGeneration=1`,
  lastError after same-second cycle: “This activity is no longer in
  the archived state you confirmed.” External cycle unarchived
  generation 1 then archived generation 2 with forced same
  `archived_at`. Current confirmation after Reload deleted. Live qs
  pid 584804 and shell.json hash unchanged. Evidence:
  `/tmp/breadcrumb-delete-gen-UgdH` (temporary).

Runtime bytes exercised on cave (workdir plugin, not live install):

| File | SHA-256 |
|---|---|
| Panel.qml | `df45cc350a7ffa5490246919361886c98b1ab3b7d1af47289c49826b4febdc99` |
| bin/breadcrumb-store | `b0fc0b77c82f71fb85644ce05a30081ebff8933a6d52bae3c43419c75ef80504` |
| bin/breadcrumb | `e39e8b17c4717ee4aa49511bfce4122b77ec32f65ca571a671cf7f61245711af` |

Working-tree tar used for those runs:
`556504df322aa155cdcf46e056f3d7207830ba9793777cf835aed4b9bd307d8e`.
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
- Historical implementation-pass limit: that candidate did not install,
  restart the shell, push, merge, or change the v0.1.0 version. Unarchive
  later merged on public main; local unpublished v0.2.0 only bumps the
  root manifest.
- Rolling a store binary back to a build that does not check
  `expected_archive_generation` reintroduces same-second `archived_at`
  ABA.

AI assistance was used to implement this slice. Owner usability
approval is not a claim that the owner audited code security.
