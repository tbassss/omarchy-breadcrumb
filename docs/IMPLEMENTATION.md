# Implementation notes for issue #6

Public local command for agent checkpoints, plus open/closed panel refresh of
external publications. Not a release, not installed, not a live SSH workflow.

Technical decisions below were recorded before production code. Issue #5 draft
CAS, generation tombstones, and UI scheduler contracts remain in force.

## Supported Omarchy APIs

Unchanged from issues #3–#5, inspected read-only on the-cave:

- Plugin contract: `manifest.json` at plugin root, `schemaVersion: 1`, `kinds` + `entryPoints`, no `omarchy.*` id, no symlinks.
- Bar widget host: `qs.Ui.Panel` + `BarIconButton` + `KeyboardPanel` + `PanelKeyCatcher`, theme via `qs.Commons`.
- Subprocess: `Quickshell.Io.Process` with `command` as a string list; JSON payload is an argv element. The **public** agent path is stdin JSON into `bin/breadcrumb`.
- Open links: `Quickshell.execDetached(open_argv)` after `validate-link`.
- Toolchain on the-cave: `/usr/bin/python3`, `/usr/bin/qs` Quickshell, Qt offscreen, `omarchy plugin validate`.
- Known full-host `qs.Ui.Button.enabled` mismatch remains issue #7. Package Button is not patched. Live host acceptance is not claimed.

## Public command boundary

Documented in [`docs/COMMAND.md`](COMMAND.md) before code.

| Decision | Choice |
|---|---|
| Public binary | `bin/breadcrumb` — not `breadcrumb-store` |
| Envelope | `"v": 1` plus `op` `list` \| `read` \| `publish` |
| Transport | stdin JSON preferred; 65536-byte cap; no shell interpolation of notes |
| Persistence | Same `breadcrumb.sqlite` and same `cmd_publish` transaction as the UI. No parallel store, sidecar, or queue. |
| Expected revision | Required integer on `publish`. No default, force, or overwrite flag. |
| Drafts | Public CLI never sends `consume_draft_revision`, never exposes save/discard/consume. Publication leaves live draft + `base_revision` untouched. |
| Read semantics | `activity_id` required. Missing store / unknown id does not create activity, database, or selected-activity pref. `list` of a missing store is empty success. |
| `has_live_draft` | Boolean hint only; draft payload is not public. |
| Author | Attribution string, not authentication. |
| Internal probe | Store `head` (read-only, no create, no selection write) is **not** a public op. |

Forbidden public keys: `consume_draft_revision`, `expected_draft_revision`, `acknowledge_base`, `force`, `overwrite`, `consume_draft`, `discard_draft`.

## Store additions (same schema v1)

- `head`: `{activity_id}` → `{activity_id, revision, checkpoint_id, saved_at}`. Does not write selected-activity. The UI probe uses this command; public CLI does not expose it. Public `list`/`read` open an existing DB read-only and do not create a missing store.
- `get` payload `select: false` skips the selected-activity write. Default remains `true` for the UI.
- Schema version stays 1. No new tables.

## UI refresh

- Closed panel: existing `onOpenedChanged: if (opened) refresh()`.
- Open panel: bounded Timer (750ms, only while `opened`) runs internal `head`. If published `revision`/`checkpoint_id` changed, enqueue `get`.
- `applySnapshot` still skips editor hydrate when `dirty` or `pendingAutosave`. After published fields update, if `(hasDraft \|\| dirty \|\| pendingAutosave) && revision > draftBaseRevision`, set `conflictPrompt` and `observedRevision`. Do not adopt published revision as draft base.
- Probe uses a dedicated Process so it does not pre-empt the FIFO scheduler. It must not drop in-flight save-draft / save-checkpoint / discard.
- No inotify cloud, no network, no FileView of the sqlite blob.

## SSH documentation

Stdin JSON over existing `ssh tbasss@the-cave`. Unreachable host = not delivered, no queue. Isolated Cave `/tmp` HOME/XDG offscreen tests are **not** a live installed SSH workflow and do not bypass the installation gate.

## Out of scope

Glance polish / `Button.enabled` host gap (#7), live install/release (#8), Kanban, merge, push, plugin enable, shell restart.

## Verification

Recorded after RED→GREEN. Python tests are not native Omarchy evidence.

### Source (Python)

RED, against `cff37d9498132cf0abfa3543542399f401b53bd6` plus the new tests and `docs/COMMAND.md` only (`bin/breadcrumb` absent):

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

Failed: 63 tests, 8 failures + 11 errors (14.775s). Missing `bin/breadcrumb`; plugin contracts for `cmd_head`, `commandPath`, `changeProbe`, and native open/closed public-CLI asserts.

GREEN, full suite from the repository root:

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
python3 -m py_compile bin/breadcrumb-store bin/breadcrumb tests/*.py
git diff --check
```

63 tests OK (17.424s), including malformed/oversized stdin, required `expected_revision`, same-revision concurrent writers (one winner), interrupted publication, receipt/readback, draft preservation, and read-without-create.

### Native (isolated component, the-cave)

Not live desktop acceptance. Unique disposable `HOME`/`XDG`, `QT_QPA_PLATFORM=offscreen`, no Wayland, no `shell.json` mutation, no plugin enable, live `qs` pid unchanged. Archive transferred with `ssh … 'cat > /tmp/breadcrumb-issue6.tar' < archive` (stdin bytes, no note interpolation). This is **not** a live installed SSH workflow and does not bypass the installation gate.

```
ARCHIVE=<working-tree tar> \
CANDIDATE_SHA=working-tree-issue6 \
EVIDENCE_DIR=/tmp/breadcrumb-evidence-s9cE \
HARNESS_SRC=tests/native/harness \
  ./tests/native/run-isolated.sh
```

Result: `validate_rc=0`, `qs_rc=0`, `ui_ok=true`, `HARNESS_OK`, `classification=component-test-not-full-host-integration`, finished `step=59`, `ticks=137`, `qmlErrors=[]`. Public CLI receipts `breadcrumb.command.v1` published revisions 7 (open panel, `has_live_draft=true`) and 8 (closed panel). Snapshots `open-panel-public` and `closed-panel-public` kept editor `open-panel in-memory draft v2`, `draftBaseRevision=6`, and `conflictPrompt=true`. Live `shell.json` sha unchanged (`469bfd9b5c8a29ff3e5e8f45a09a66729eaf6a4e4b42462cf26fc99f4102eaee`); live `qs` pid 1600 unchanged; live plugin dir still had no `tbassss.breadcrumb`. `ui-results.json` sha256 `51b38c21bbcf02dfd8c8f78ee6ec9f36f5deed4fad13756472527f1988d1bc7f`.

### Classification

| Check | Kind |
|---|---|
| `unittest discover -s tests` | Source-contract / store / public CLI process |
| Isolated `tests/native/` on the-cave | Native component (real Panel.qml + qs + Qt offscreen) |
| Live installed SSH workflow | **Not run.** Installation gate. |
| Full omarchy-shell bar / KeyboardPanel / Button.enabled | **Not run.** Issue #7. |

## Remaining blockers

- Independent persistence/concurrency review (parent-owned; required before merge).
- Glance polish and the known full-host `Button.enabled` mismatch are issue #7.
- Live install, restart, merge, and release remain unapproved.
- This slice is not release-ready.
