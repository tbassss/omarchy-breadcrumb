# Implementation notes for issue #3

First persistent manual checkpoint. Not a release, not installed, not an agent CLI.

## Supported Omarchy APIs inspected (read-only on the-cave)

- Plugin contract: `manifest.json` at plugin root, `schemaVersion: 1`, `kinds` + `entryPoints`, no `omarchy.*` id, no symlinks. Validated by `omarchy plugin validate` / `PluginRegistry.qml`.
- Bar widget host: `qs.Ui.Panel` + `BarIconButton` + `KeyboardPanel` + `PanelKeyCatcher`, theme via `qs.Commons` (`Color`, `Style`).
- Subprocess: `Quickshell.Io.Process` with `command` as a string list; `StdioCollector { waitForEnd: true }`. JSON payload is an argv element, not a shell string. Network panel writes secrets with `stdinEnabled`/`write()`; this slice uses argv JSON because checkpoint payloads are small and Process does not expose close-stdin.
- Open links: `Quickshell.execDetached(open_argv)` after the store returns `["xdg-open", "--", target]`. No `bash -c` interpolation.
- Do not depend on `io.github.tyrichards.tray` or other custom shell patches.
- Toolchain on the-cave: `/usr/bin/python3` 3.14, `/usr/bin/qs` Quickshell 0.3.1, `omarchy plugin validate`.

## Storage

- Python 3 stdlib `sqlite3` only.
- Default directory: `$XDG_DATA_HOME/breadcrumb` or `~/.local/share/breadcrumb` (0700). Override: `BREADCRUMB_DATA_DIR`.
- Database `breadcrumb.sqlite` (0600), schema version 1.
- Rollback journal (`PRAGMA journal_mode=DELETE`) and `PRAGMA synchronous=FULL`.
- Stable activity UUIDs. Checkpoints are append-only; current is `MAX(revision)`.
- Publication uses `BEGIN IMMEDIATE` plus `expected_revision` CAS. Stale writers fail without writing.
- `bin/breadcrumb-store` is the UI persistence seam. It is not the public agent command from issue #6.

## Out of scope (#4–#8)

Activity switching/rename/archive, history browser, disk draft recovery, public agent CLI, glance polish, live install/release.

## Native save/reopen evidence (component test, 2026-09-09)

Python tests and QML source contracts are not native Omarchy evidence. Isolated qs
offscreen harness lives at `tests/native/` and must run on the-cave only.

Classification: **component test** — real `Panel.qml` + `/usr/bin/qs` 0.3.1 + Qt
6.11.2 offscreen. Host `qs.Ui` / `qs.Commons` are a minimal facade of inspected
Cave APIs. `KeyboardPanel` is stubbed to avoid WlrLayershell. Not full
omarchy-shell host integration, not a live bar, not a live install.

### Qt control APIs inspected (read-only on the-cave)

- `/usr/share/omarchy/shell/Ui/TextField.qml` inherits Qt Quick Controls
  `TextField` (`QQuickTextField` : `QQuickTextInput`). `textEdited` is inherited
  from `QQuickTextInput` and does **not** fire for programmatic `text` changes.
- QtQuick.Controls `TextArea` is `QQuickTextArea` : `QQuickTextEdit`.
  `textEdited` exists on this Cave Qt 6.11.2 (`Q_REVISION(6, 9)`).
- Omarchy `Dropdown.qml` emits `changed` only on user option select, not on
  construction.

Rejected candidate `6924a94` marked `dirty` from `onTextChanged` during
TextField/TextArea construction, so the first `get` skipped editor hydration.
Repair uses `onTextEdited` for dirty. `get` still does **not** clear dirty
(would clobber a genuine in-progress edit on refresh).

### Isolated re-run

```bash
# On the-cave. Disposable HOME/XDG only. Do not write ~/.config/omarchy of the live user.
ARCHIVE=/path/to/plugin.tar \
EVIDENCE_DIR=/tmp/breadcrumb-evidence \
HARNESS_SRC=/path/to/checkout/tests/native/harness \
  /path/to/checkout/tests/native/run-isolated.sh
```

Holds: `QT_QPA_PLATFORM=offscreen`, unique `XDG_RUNTIME_DIR`, no Wayland/DISPLAY,
no live plugin enable, no shell.json mutation, no service restart.

### Results (repair working tree vs rejected `6924a94`)

| Check | Rejected `6924a94` | Repair |
|---|---|---|
| `omarchy plugin validate` | PASS rc=0 | PASS rc=0 |
| UI create + save + close/open | PASS | PASS |
| Same-instance in-memory draft refresh | PASS | PASS |
| Loader recreate `current.*` | PASS | PASS |
| Loader recreate editor (`editSummary===current.summary`, `dirty===false`) | **FAIL** empty editor, `dirty=true` | **PASS** |
| QML runtime errors | none | none |
| Live `shell.json` hash | unchanged `469bfd9b…` | unchanged `469bfd9b…` |
| Live plugin dir `tbassss.breadcrumb` | absent | absent |

Fictional checkpoint only. Native assertion is `tests/native/harness/shell.qml`,
not a source-only substitute.

### Not claimed

- Full host integration (live bar, real `KeyboardPanel` layer-shell, `IpcHandler`)
- Issue #4–#8 (history, disk drafts, agent CLI, glance polish, live install)
- Disk draft recovery after Panel recreate (issue #5). Recreate hydrates from
  the saved checkpoint; in-memory drafts are same-instance only.
