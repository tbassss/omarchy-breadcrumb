# Issue #8 release-candidate verification

## Current status (supersedes historical prep below)

Installed and independently source-reviewed runtime candidate:
`9cdf2a75f34e197e2f0eea1327561959fbd27739`.
Panel SHA-256: `32f61045d6c17faacd964de79205fcf27c1fd3fd3f381ad95dc5239b3329f18d`.
Store bytes remain unchanged from the base. Do not reinstall the older disk-icon base.
Subsequent documentation-only commits do not change this runtime identity.

Independent AI-assisted review: 70 tests passed, no new runtime defect.
See [review report](FINAL_REVIEW.md) for exact scope and limitations.
The review did **not** clear issue #8 closure or publication.

Issue #8 records owner-confirmed live save/reopen, activity isolation/archive,
agent update with draft preservation, explicit conflict resolution, history restore,
draft recovery through shell restart, accepted bread icon, and removal/reinstall.
Removal/reinstall preserved the exact logical database; shell config was unchanged.
Private rollback backup on Cave: `~/.local/state/breadcrumb-reinstall/20260909-152858`
(plugin, shell.json, SQLite online backup, receipt). Restore only under explicit
approval; never automatically overwrite current user data with an older backup.

Subsequent owner checks confirmed live theme colors after reopening, placement on
both monitors, scroll access to Save/History, Escape closure, switching to the
volume popup, and Compact published content with a separate draft indicator.

Final native rerun against `0ecb440968d5754b5cb17a8e9be62b58ff41d78e`
(documentation-only successor of the runtime above) passed: runner/validation/qs
exit 0, ui_ok=true, step=96, qmlErrors=[], hung launcher timeout/reap verified.
Composer checked archive SHA-256 and Panel/store equality against local source.
See [native report](FINAL_NATIVE_VERIFICATION.md). Packaged controls ran with host
Panel/KeyboardPanel stubs; live owner checks supply separate host evidence.

Residual coverage limits: no separate Compact-only restart journey, every-theme
matrix, live hard-crash injection, or owner exercise of every alternate conflict /
missing-file path. Relevant store/component tests cover those implemented paths;
these limits are disclosed, not claims of additional live passes. Source review
and the completed live/component evidence support presenting the private candidate
for owner merge approval, not public release or listing approval.

Repository remains private. Merge, public visibility, tag/release, and directory
submission remain separate approvals. None was performed by this review.

## Historical preparation snapshot — not current installation instructions

Everything below records the initial pre-install preparation at the old base.
Its hashes, counts, unrun checks and absence statements are historical, not current
candidate identity or current blockers. Consult the current status above and issue #8.


Not a published release. Not a directory listing. Not live-installed.
Parent owns frozen review, merge, publication, and listing.

## Candidate identity

| Field | Value |
|---|---|
| Branch | `release/first-candidate` |
| Base plugin bytes | `80eb9b6752dd59e30aa34cb6aaf499f470845438` (`feat: native interface polish and control compatibility (#13)`) |
| Plugin id | `tbassss.breadcrumb` |
| Manifest version | `0.1.0` (not announced) |
| License | MIT, owner-approved 2026-09-09. Copyright (c) 2026 tbassss. |
| Repo visibility | **private** (`tbassss/omarchy-breadcrumb`) |
| Issue | [#8](https://github.com/tbassss/omarchy-breadcrumb/issues/8) |

`bin/breadcrumb-store` sha256 at that base:
`c74d7275d66c678a3e30c70f3fb2e1fbb74f2542274ef2c44986330d52ff9d84`.
`Panel.qml` sha256:
`21449ed07d5280beee5dd35a58b241b82773105da5c185a1f9638e673ac6d2e1`.

This prep commit adds LICENSE, docs, fictional isolated screenshots, and
contract checks. It does not change plugin runtime behavior.

## Supported host (read-only inspection, the-cave)

Omarchy `4.0.3-1`, Quickshell `0.3.1`, Python `3.14.7`, Qt `6.11.2`.

Host plugin contract (`PluginRegistry.validateManifest`):

- Required: `schemaVersion === 1`, `id`, `name`, `version`, `kinds`, `entryPoints`
- `id` must not start with `omarchy.`
- Entry paths must be relative, no `..`, no absolute, no symlink
- `bar-widget` enable writes `shell.json` bar layout (`defaultSection` or placement)

Breadcrumb matches the **combined** first-party bar-widget pattern
(`Panel` + `BarIconButton` + `KeyboardPanel`), same as packaged
`omarchy.audio` / `omarchy.power`. Split `BarWidget.qml` + nested `Panel.qml`
is used by clock/weather because they need extra IPC; it is not required for
this plugin. `Bar.findPanelWidget` requires `open`/`close`/`opened` on the
bar-widget root; `qs.Ui.Panel` provides those.

Independent of custom Tray: source does not import
`io.github.tyrichards.tray`. Packaged `BarModel.pinTrayToInner` only pins
`omarchy.tray`. Live right section currently starts with the custom tray;
placement next to it is a dogfood item, not a source dependency.

## plugins.omarchy.org listing (current, not submitted)

Reviewed 2026-09-09: [plugins.omarchy.org/publish.html](https://plugins.omarchy.org/publish.html)
and [develop.html](https://plugins.omarchy.org/develop.html). Registry UI
showed **0** community plugins.

Listing wants:

1. **Public** GitHub repository (blocker: this repo is private)
2. Valid root `manifest.json`
3. README and license (LICENSE now present)
4. Safe install and removal (documented; **not** live-verified)
5. Optional preview (fictional isolated screenshots prepared)
6. Submit via the directory issue form; automated validation of the current
   commit; marketplace validates listings **not** plugin security

Do **not** submit. Public visibility and listing are separate approvals.

Host kinds currently documented: `bar-widget`, `panel`, `overlay`, `menu`,
`service`, `bar`. Breadcrumb uses `bar-widget` only.

## Privacy audit (complete Git history + tracked bytes)

19 commits, 227 historical objects, 58 historical paths, 44 tracked files
at the base (~413 KiB). No SQLite, no `.env`, no credential files, no
runtime-data, no personal screenshots in history.

| Class | Result |
|---|---|
| Credential-shaped blobs (API keys, tokens, PEM, AWS, GitHub PAT, `BEGIN PRIVATE`) | **none** |
| Tracked checkpoint databases / `runtime-data/` / `private/` | **none** |
| Personal/WGU/health checkpoint payloads | **none** (fixtures are fictional: Study, App Project, Personal, Fictional Garden Path) |
| Large/binary history objects | **none** |
| Author identity in commit metadata | git author emails exist (public identity, not secrets) |
| Live Cave paths in tests | `tests/native/run-isolated.sh` names `/home/tbasss/.config/omarchy/shell.json` only as a **refuse-if-present** isolation check |

`.gitignore` already excludes `.env`, `__pycache__`, `runtime-data/`,
`private/`, `*.sqlite`. Untracked local `__pycache__` is not in git.

## Tests run for this prep

### Source (VPS, this tree)

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
python3 -m py_compile bin/breadcrumb-store bin/breadcrumb tests/*.py
git diff --check
```

69 tests OK (16.208s) after LICENSE/docs edits.

### Isolated native (the-cave, ungated)

Unique `/tmp/breadcrumb-native-*` `HOME`/`XDG`, `QT_QPA_PLATFORM=offscreen`.
No Wayland, no live plugin enable, no `shell.json` write, live qs pid `1494`
unchanged, live plugin dir still absent.

```
ARCHIVE=/tmp/breadcrumb-issue8-20260909212440/candidate.tar
CANDIDATE_SHA=80eb9b6752dd59e30aa34cb6aaf499f470845438
EVIDENCE_DIR=/tmp/breadcrumb-issue8-20260909212440/evidence
```

Result: `validate_rc=0`, `qs_rc=0`, `ui_ok=true`, `HARNESS_OK`,
`classification=component-test-not-full-host-integration`, `step=96`,
`hangElapsedMs=8042`, `qmlErrors=[]`.
`shell.json` sha unchanged
`469bfd9b5c8a29ff3e5e8f45a09a66729eaf6a4e4b42462cf26fc99f4102eaee`.

Durable copy: `/home/hermes/breadcrumb-issue8-prep-evidence/` (outside git,
except fictional PNGs under `docs/screenshots/`).

These are **not** live KeyboardPanel / live bar acceptance.

## Host Panel / KeyboardPanel boundary

Inspected live `/usr/share/omarchy/shell/Ui/{Panel,KeyboardPanel}.qml`.

| Host type | Isolated harness | Live meaning |
|---|---|---|
| `qs.Ui.Panel` | Item stub, local open/close, no `PanelController`/`IpcHandler` | Combined bar-widget base; IPC summon untested |
| `qs.Ui.KeyboardPanel` | Sized Item stub, cap-aware `fittedContentHeight` | `PanelWindow` + WlrLayershell; **must not** instantiate offscreen |

Concrete differences (not repaired here):

1. **Live KeyboardPanel is untested.** Instantiating the packaged type
   attaches to the compositor. Isolated tests cannot prove popup
   placement, exclusive-zone, focus steal, or Escape-to-close on the real
   layer shell. Safe reproduction after owner install: click the bar icon,
   confirm popup anchors to the icon, Escape closes, other popouts close
   this one via inherited `closeForPopoutSwitch`.
2. **`fittedContentHeight` inset.** Host adds `verticalContentInset`
   (`padding*2` + border) to the implicit height, then applies the cap.
   The isolated stub does not add that inset. Live card height can exceed
   isolated screenshots by that inset while still capped at
   `Style.space(520)`. Plugin call site matches first-party audio
   (`fittedContentHeight(column.implicitHeight, Style.space(520))`).
   Safe reproduction: compare a live popup screenshot to
   `docs/screenshots/screenshot-expanded.png`.
3. **Host KeyboardPanel `required property` `anchorItem` and `bar`.**
   Breadcrumb binds `anchorItem: button` and `bar: root.bar`, same as
   `omarchy.audio`. Isolated stub does not mark them required. No unique
   Breadcrumb defect found; live null-`bar` construction is a first-party
   pattern, not repaired.

No QML API misuse unique to Breadcrumb was found that should be patched
without live evidence. Do not treat this as full-host clearance.

## Spec journeys vs evidence

| Journey | Evidence |
|---|---|
| 1 Create/switch Study, App Project, Personal | Isolated native + store tests. Not live bar. |
| 2 Restart shell, Compact reopen | **Not run.** Needs install + restart approval. |
| 3 Theme / dual-monitor / popup placement | **Not run.** |
| 4 Agent command over existing SSH | Isolated public CLI + docs. Live installed SSH **not run**. |
| 5 Unreachable host = not delivered | Documented. No queue exists. |
| 6 Stale Save / Keep editing / Overwrite | Store + isolated native. Not live bar. |
| 7 Crash mid-edit draft recover | Store + isolated recreate. Not live crash of qs. |
| 8 History restore appends new revision | Store + isolated native. |
| 9 Keyboard / overflow / theme/monitor | Isolated keyboard/overflow only. Theme/monitor **not run**. |
| 10 Install, manual use, remove preserves data | Semantics inspected in `omarchy-plugin-{add,remove,enable,disable}`. **Live install/remove not run.** |

## Blockers (issue #8 cannot close)

1. Owner-approved **live install / enable / possible shell restart** and
   **remove** on The Cave ([LIVE_TEST_PLAN.md](LIVE_TEST_PLAN.md)).
2. Owner **usability dogfood** on the live bar (manual + optional command).
3. Independent frozen-candidate **persistence/concurrency review** (parent).
4. **Public visibility** still private; listing requires a public GitHub repo.
5. GitHub release / tag / plugins.omarchy.org submission — separate
   approvals, not this issue.
6. Live KeyboardPanel / dual-monitor / theme still unproven.

## Smallest human gates

1. Approve live test plan (install + enable; restart only if widget missing).
2. Use it for a real session with fictional or owner-chosen notes; write
   usability feedback.
3. Approve rollback (disable + remove); confirm XDG data remains.
4. Parent independent review of the frozen SHA.
5. Later, separately: public repo, then listing, then GitHub release.
   Do not announce `0.1.0` as shipped until those exist.
