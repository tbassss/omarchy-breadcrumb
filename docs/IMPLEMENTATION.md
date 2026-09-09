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
- Open links: `Process` argv seam (`openProc`) after `validate-link`. No shell. `BREADCRUMB_NO_OPEN=1` skips real `xdg-open`. Startup and nonzero failures set `lastError`. Isolated tests use fake argv launchers, never live apps.

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
| Links | Open only after `validate-link`. Missing file/folder → `not_found`. Launch uses argv `Process` (no shell, bounded timeout). Isolated tests set `BREADCRUMB_NO_OPEN=1` and drive fake launchers for success / nonzero / start-failure. |
| Keyboard | Packaged `PanelKeyCatcher` (`Keys.BeforeItem`). `blocked` when any editor is focused or any dropdown `popupOpen`. `j/k` move a cursor; Return/Space activate. Busy Expand is not `focusable`. |
| Expanded viewport | Main column is `panelScroller` (Flickable). `contentHeight` is `fittedContentHeight(..., Style.space(520))`. Focus/cursor calls `revealItem`. |

`validate-link` now checks that file/folder targets exist and that kind matches
the path type. This is the Open adapter, not publish/CAS/draft persistence.
Publishing a checkpoint may still store a link to a path that does not exist yet.

## Isolated native harness

`tests/native/run-isolated.sh` copies packaged `/usr/share/omarchy/shell/{Commons,Ui}`
into the disposable harness, then overlays repo stubs for:

- `KeyboardPanel.qml` — real type is WlrLayershell `PanelWindow`. The stub applies `defaultHeightCap: 520` so isolated geometry matches a capped host, not an unbounded implicit height.
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

Repair of rejected `ddd3134` (this candidate): RED then GREEN for the three
blocked UI/adapter failures. Independent fake-launcher tests live in
`tests/test_open_launch.py` (success / nonzero / missing binary; no `xdg-open`,
no shell). Source contracts forbid `execDetached`, require `openProc`, catcher
`blocked: root.catcherBlocked`, `panelScroller`, and cap-aware
`fittedContentHeight(..., Style.space(520))`.

GREEN, full suite from the repository root after the repair:

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
python3 -m py_compile bin/breadcrumb-store bin/breadcrumb tests/*.py
git diff --check
```

69 tests OK. Store/CAS/draft/publication tests unchanged in behavior.

### Native (isolated component, the-cave)

Not live desktop acceptance. Unique disposable `HOME`/`XDG`, `QT_QPA_PLATFORM=offscreen`,
no Wayland, no `shell.json` mutation, no plugin enable, live `qs` pid unchanged.
Archive transferred with `ssh … 'cat > /tmp/breadcrumb-issue7.tar' < archive`
(stdin bytes, no note interpolation). `BREADCRUMB_NO_OPEN=1` so Open records argv
and does not call `xdg-open`. Fake launchers are argv Python scripts in the
disposable workdir.

```
ARCHIVE=<plugin tar> \
CANDIDATE_SHA=<git sha> \
EVIDENCE_DIR=/tmp/breadcrumb-issue7-20260909191625-13635/evidence \
HARNESS_SRC=tests/native/harness \
  ./tests/native/run-isolated.sh
```

Result: `validate_rc=0`, `qs_rc=0`, `ui_ok=true`, `HARNESS_OK`,
`classification=component-test-not-full-host-integration`, finished `step=96`,
`ticks=513`, `qmlErrors=[]`.

Packaged overlay: `button_declares_enabled=0`; Dropdown `selectCurrent()` is the
no-arg installed API; packaged `PanelKeyCatcher` and Dropdown are overlaid
(SHAs in `/home/hermes/breadcrumb-issue7-final-evidence/logs/overlay-files.sha256`).
Catcher Return on a non-editor descendant (`catcherFocus`) expanded Compact→Expanded.
Editor focus blocked the catcher; `j` inserted into the summary (`ovej` → `ovejj`),
not merely left Expanded. Packaged Dropdown `popupOpen` blocked the catcher so
Down/Up/Return/Tab did not drive the panel cursor.

Capped geometry (not the rejected 1393/1820 inflated stub screenshots):
expanded panel `720×520` with `panelScroller.contentHeight=1393` and
`contentY=80`; narrow `360×520` with `contentHeight=1820`. Compact glance
`summaryHeight=32` at width 380.

Narrow `360×520` keyboard Tab/Down/Up/j after actual traversal (no assigned
`contentY`): Save `contentY=540` contained; Links Add link `contentY=502`
contained; History Restore `contentY=948` contained. Save Return published
revision 9→10. Links Return added a row. History Return showed the dirty-draft
guard (`Save or discard the current edit before restoring history.`) instead of
clobbering the draft. Screenshots after traversal:
`screenshot-narrow-save.png`, `screenshot-narrow-links.png`,
`screenshot-narrow-history.png` (each 360×520).

Process launch (fake argv, no real apps): success `openLaunchState=exited`
exit 0; nonzero exit 2 visible `Could not open that link.`; missing launcher
start-failure same visible error. Hanging fake launcher hit production
`openTimeout` `interval: 8000` (`hangElapsedMs=8043`), visible
`Could not open that link.`, `openLaunchState=failed`, `openProcRunning=false`,
child pid 30756 reaped (`reapCheckExit=0`, exit 15/SIGTERM). Argv was the hang
script, not a live `xdg-open`. Safe web Open still recorded
`["xdg-open","--","https://example.com/notes"]` without launching. Missing-file
error visible (`That file or folder is missing.`). Remember-view recreate stayed
Expanded. Live `shell.json` sha unchanged
(`469bfd9b5c8a29ff3e5e8f45a09a66729eaf6a4e4b42462cf26fc99f4102eaee`); live `qs`
pid 1494 unchanged; live plugin dir still had no `tbassss.breadcrumb`.
Store SHA unchanged `c74d7275d66c678a3e30c70f3fb2e1fbb74f2542274ef2c44986330d52ff9d84`.

Production change for this remaining evidence: `keyboardTargets` now includes
Save, Links Open/Add link, and History Restore, with `revealItem` on focus and
Return activation. That is the minimal focus/reveal fix so j/Down can reach
those controls in the capped 360×520 viewport.

Fictional isolated screenshots (copied locally, not committed):

- `/home/hermes/breadcrumb-issue7-final-evidence/screenshots/screenshot-compact.png` (380×277)
- `/home/hermes/breadcrumb-issue7-final-evidence/screenshots/screenshot-expanded.png` (720×520)
- `/home/hermes/breadcrumb-issue7-final-evidence/screenshots/screenshot-narrow.png` (360×520)
- `/home/hermes/breadcrumb-issue7-final-evidence/screenshots/screenshot-many-activities.png` (720×520)
- `/home/hermes/breadcrumb-issue7-final-evidence/screenshots/screenshot-narrow-save.png` (360×520)
- `/home/hermes/breadcrumb-issue7-final-evidence/screenshots/screenshot-narrow-links.png` (360×520)
- `/home/hermes/breadcrumb-issue7-final-evidence/screenshots/screenshot-narrow-history.png` (360×520)

Cave originals: `/tmp/breadcrumb-issue7-final-20260909130243-30414/evidence/`.
Durable copy: `/home/hermes/breadcrumb-issue7-final-evidence/` (candidate.tar, harness, overlay controls+SHAs, JSON, logs, screenshots, versions).

### Classification

| Check | Kind |
|---|---|
| `unittest discover -s tests` | Source-contract / store / public CLI process |
| `tests/test_open_launch.py` fake argv Process outcomes | Source process seam (no QML runtime, no real apps) |
| Isolated `tests/native/` on the-cave with packaged Button/Dropdown/TextField/PanelKeyCatcher/Color/Style | Native component (real Panel.qml + qs + Qt offscreen + packaged controls) |
| KeyboardPanel / host Panel | **Stubbed.** WlrLayershell / IpcHandler would attach to the compositor or live IPC. Stub is cap-aware (`defaultHeightCap` 520). |
| Live installed SSH workflow / bar | **Not run.** Installation gate. |
| Dual-monitor / live theme / layershell | **Not run.** Requires owner approval. |

## Remaining blockers

- Independent persistence/concurrency review (parent-owned; required before merge). `validate-link` existence checks are Open-adapter only; CAS/draft rules unchanged.
- Live install, restart, owner dogfood, merge, and publication remain unapproved (#8). See `docs/RELEASE_PREP.md` and `docs/LIVE_TEST_PLAN.md`.
- Dual-monitor, live theme swap, and real KeyboardPanel layershell are **not** claimed.
- This slice is not a published release.
