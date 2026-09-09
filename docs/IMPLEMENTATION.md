# Implementation notes for issue #7

Compact/Expanded polish and host-control compatibility. Not a release, not
installed, not a live bar or dual-monitor/theme test.

Technical decisions below were recorded after read-only inspection of installed
Omarchy APIs on the-cave and before production UI changes. Issue #5 draft CAS,
generation tombstones, and UI scheduler contracts remain in force. Issue #6
public command contracts remain in force. Persistence/CAS/draft rules were not
changed except `validate-link` existence checks used only on explicit Open.

AI assistance was used to implement this slice. Owner usability approval is not
a claim that the owner audited code security.

## Supported Omarchy APIs

Inspected read-only on the-cave (`tbasss@the-cave`, no package patches):

- Omarchy `4.0.3-1`, Quickshell `0.3.1`, Python `3.14.7`, Qt 6.11.2
- Plugin contract: `manifest.json` at plugin root, `schemaVersion: 1`
- Bar widget host: `qs.Ui.Panel` + `BarIconButton` + `KeyboardPanel` + `PanelKeyCatcher`
- Theme: `qs.Commons.Color` (`foreground`, `urgent`, `muted`) and `Style.space` / `Style.font`
- `qs.Ui.Button` (installed): `text`, `foreground`, `fontFamily`, `fontSize`, `bordered`, `focusable`, `selected`, `clicked`. **No `enabled` property.** Keyboard Return/Space fires `clicked` only when `focusable`.
- `qs.Ui.Dropdown.selectCurrent()` takes **no argument**; it assigns `root.value` from `currentIndex` then emits `changed`.
- Subprocess: `Quickshell.Io.Process` with `command` as a string list
- Open links: `Quickshell.execDetached(argv)` after `validate-link`, skipped when `BREADCRUMB_NO_OPEN=1`

Package Button was not patched. The plugin no longer assigns `enabled:` on
`qs.Ui.Button`. Clicks are guarded in `onClicked`; visual disable uses `opacity`;
keyboard uses `focusable`.

## UI / adapter decisions

| Decision | Choice |
|---|---|
| First-use view | Compact. `set-view` still persists compact/expanded. Recreate reloads prefs. |
| Compact glance | `maximumLineCount: 2` + `elide` on summary and next step. Full text lives in Expanded. |
| Timestamp / author | `Model.formatSavedAt` + “reported by”. Attribution is not authentication. |
| Draft indicator | Compact still shows published checkpoint; “Unsaved draft — expand to continue editing.” |
| Stale-report | Explicit “Stale-report: A newer checkpoint was saved after this draft…” |
| Narrow expanded | `Grid` stacks sidebar above editor when `column.width < Style.space(560)` |
| Many activities | Flickable `activityScroller` capped at `Style.space(220)` |
| Links | Open only after `validate-link`. Missing file/folder → `not_found`. No shell interpolation. Isolated tests set `BREADCRUMB_NO_OPEN=1` and record `lastOpenArgv`. |

`validate-link` now checks that file/folder targets exist and that kind matches
the path type. This is the Open adapter, not publish/CAS/draft persistence.
Publishing a checkpoint may still store a link to a path that does not exist yet.

## Isolated native harness

`tests/native/run-isolated.sh` copies packaged `/usr/share/omarchy/shell/{Commons,Ui}`
into the disposable harness, then overlays repo stubs for:

- `KeyboardPanel.qml` — real type is WlrLayershell `PanelWindow`
- `Panel.qml` — real type wires `PanelController` + `IpcHandler`

Remaining host types used in this run are the packaged files (Button, Dropdown,
TextField, BarIconButton, PanelKeyCatcher, Color, Style, Border, Util, …).

Classification: **component-test-not-full-host-integration**. Not a live bar
install. Not layershell, dual-monitor, or live theme acceptance.

## Out of scope

Live install/enable/restart (#8), Kanban, merge, push, plugin enable, shell
restart, dual-monitor, live theme swap, WlrLayershell KeyboardPanel.

## Verification

Recorded after RED→GREEN. Python tests are not native Omarchy evidence.

### Source (Python)

RED, against `9f92efa5c47ee890fa17f39c99e7b47e2ab4098c` plus new tests only:

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests.test_plugin_contract tests.test_store.TestStore.test_validate_link_reports_missing_file_without_shell -v
```

Failed: Button `enabled` still present, missing `launchOpenArgv` / `maximumLineCount` / native polish asserts, missing-file `validate-link`.

GREEN, full suite from the repository root:

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
python3 -m py_compile bin/breadcrumb-store bin/breadcrumb tests/*.py
git diff --check
```

64 tests OK (18.580s), including missing-file `not_found` without shell metacharacters.

### Native (isolated component, the-cave)

Not live desktop acceptance. Unique disposable `HOME`/`XDG`, `QT_QPA_PLATFORM=offscreen`,
no Wayland, no `shell.json` mutation, no plugin enable, live `qs` pid unchanged.
Archive transferred with `ssh … 'cat > /tmp/breadcrumb-issue7.tar' < archive`
(stdin bytes, no note interpolation). `BREADCRUMB_NO_OPEN=1` so Open records argv
and does not call `xdg-open`.

```
ARCHIVE=<plugin tar> \
CANDIDATE_SHA=working-tree-issue7 \
EVIDENCE_DIR=/tmp/breadcrumb-evidence-issue7-ykjx \
HARNESS_SRC=tests/native/harness \
  ./tests/native/run-isolated.sh
```

Result: `validate_rc=0`, `qs_rc=0`, `ui_ok=true`, `HARNESS_OK`,
`classification=component-test-not-full-host-integration`, finished `step=80`,
`ticks=168`, `qmlErrors=[]`.

Packaged overlay: `button_declares_enabled=0`; Dropdown `selectCurrent()` is the
no-arg installed API. Keyboard Return on the Expand button toggled Compact→Expanded.
Compact long-text geometry `summaryHeight=32` at width 380. Expanded editor kept
480-character full text. Narrow stacked at width 360. Missing-file error visible
(`That file or folder is missing.`). Safe web Open recorded
`["xdg-open","--","https://example.com/notes"]` without launching. Remember-view
recreate stayed Expanded. Live `shell.json` sha unchanged
(`469bfd9b5c8a29ff3e5e8f45a09a66729eaf6a4e4b42462cf26fc99f4102eaee`); live `qs`
pid 1600 unchanged; live plugin dir still had no `tbassss.breadcrumb`.
`ui-results.json` sha256 `c95c20792beadff116edbb7e9d40495534d5bbeb8df4e98a46d8de4e60861860`.

Fictional isolated screenshots (copied locally, not committed):

- `/tmp/breadcrumb-issue7-evidence/screenshots/screenshot-compact.png`
- `/tmp/breadcrumb-issue7-evidence/screenshots/screenshot-expanded.png`
- `/tmp/breadcrumb-issue7-evidence/screenshots/screenshot-narrow.png`
- `/tmp/breadcrumb-issue7-evidence/screenshots/screenshot-many-activities.png`

Cave originals: `/tmp/breadcrumb-evidence-issue7-ykjx/screenshots/`.

### Classification

| Check | Kind |
|---|---|
| `unittest discover -s tests` | Source-contract / store / public CLI process |
| Isolated `tests/native/` on the-cave with packaged Button/Dropdown/TextField/Color/Style | Native component (real Panel.qml + qs + Qt offscreen + packaged controls) |
| KeyboardPanel / host Panel | **Stubbed.** WlrLayershell / IpcHandler would attach to the compositor or live IPC. |
| Live installed SSH workflow / bar | **Not run.** Installation gate. |
| Dual-monitor / live theme / layershell | **Not run.** Requires owner approval. |

## Remaining blockers

- Independent persistence/concurrency review (parent-owned; required before merge). `validate-link` existence checks are Open-adapter only; CAS/draft rules unchanged.
- Live install, restart, merge, and release remain unapproved (#8).
- Dual-monitor, live theme swap, and real KeyboardPanel layershell are **not** claimed. Smallest proposed approved operation, if wanted later: a nested/throwaway Hyprland session that is **not** the user's live desktop, still without writing `~/.config/omarchy/shell.json` of the live user. Exact command is not run here.
- `Quickshell.execDetached` cannot report `xdg-open` failures after launch; missing-file/kind mismatches are shown before launch.
- This slice is not release-ready.
