# Breadcrumb final isolated native verification

**Historical isolated native rerun** of the first-candidate runtime.
Not current v0.2.0 evidence. Identity, hashes, and step counts are
preserved as written.

Executed 2026-09-09T15:47:34-07:00 on the-cave. Not a live bar install. No repository edits, no live plugin/data/config mutation, no restart, no real launcher, no publish.

## Candidate identity

| Field | Value |
|---|---|
| HEAD (docs-only successor) | `0ecb440968d5754b5cb17a8e9be62b58ff41d78e` |
| Runtime commit | `9cdf2a75f34e197e2f0eea1327561959fbd27739` |
| HEAD vs runtime | docs only: CONTRIBUTING.md, README.md, docs/FINAL_REVIEW.md, docs/ICON_ACCEPTANCE.md, docs/PRODUCT_SPEC.md, docs/RELEASE_PREP.md (6 files, +139/−9) |
| `Panel.qml` SHA-256 | `32f61045d6c17faacd964de79205fcf27c1fd3fd3f381ad95dc5239b3329f18d` (HEAD blob, git archive, live installed plugin — identical) |
| `bin/breadcrumb-store` SHA-256 | `c74d7275d66c678a3e30c70f3fb2e1fbb74f2542274ef2c44986330d52ff9d84` (HEAD, archive, live installed — identical) |
| Authenticated archive | `git archive --format=tar HEAD` → `/tmp/breadcrumb-final-native-20260909224642/candidate.tar` |
| Archive SHA-256 | `b736091fb18a1603dcfb0b636025b4197c73d688f6ee86d2ce538cd6d1a8fc97` (local and remote evidence copy match) |
| Live installed git HEAD | `9cdf2a75f34e197e2f0eea1327561959fbd27739` (unchanged) |

## Run

Existing `tests/native/run-isolated.sh` against the authenticated HEAD archive.

```
ARCHIVE=/tmp/breadcrumb-final-native-20260909224642/candidate.tar
CANDIDATE_SHA=0ecb440968d5754b5cb17a8e9be62b58ff41d78e
EVIDENCE_DIR=/tmp/breadcrumb-final-native-20260909224642/evidence
HARNESS_SRC=/tmp/breadcrumb-final-native-20260909224642/tests/native/harness
LIVE_PLUGIN_DIR=/tmp/breadcrumb-final-native-20260909224642/empty-plugins
```

Host: Omarchy `4.0.3-1`, Quickshell `0.3.1`, Python `3.14.7`. Packaged overlay from `/usr/share/omarchy/shell`. Stubbed only `KeyboardPanel` and host `Panel`. Isolated `HOME`/`XDG`, `QT_QPA_PLATFORM=offscreen`, workdir `/tmp/breadcrumb-native-Dq5j`. Fake argv launchers only; `BREADCRUMB_NO_OPEN=1`.

`LIVE_PLUGIN_DIR` override: the existing runner refuses if `/home/tbasss/.config/omarchy/plugins/tbassss.breadcrumb` exists. That path is now the approved live install. Harness source was not edited. The env var pointed at an empty disposable dir so the refuse-if-present / created-unexpectedly checks still apply to a non-live path. Real live plugin and `shell.json` were hashed independently before and after.

## Results

| Check | Result |
|---|---|
| `run-isolated.sh` rc | **0** |
| `omarchy plugin validate` | `validate_rc=0` (empty stdout) |
| `qs_rc` | **0** |
| `ui_ok` | **true** |
| `HARNESS_OK` | yes |
| finished `step` | **96** |
| `ticks` | **514** |
| `qmlErrors` | `[]` |
| `hangElapsedMs` | **8042** (production 8s timeout) |
| `reapCheckExit` | **0** |
| extra asserts (traversal contained save/links-open/history-restore; editor `j`; dropdown `popupOpen`) | **ok** |
| classification | `component-test-not-full-host-integration` |
| qs stderr | empty (0 bytes) |

`BREADCRUMB_RESULTS` file was missing (`NO_UI_RESULTS_FILE`); runner recovered `ui-results.json` from stdout (`recovered_ui_results_from_stdout bytes 152679`). Extra asserts then passed. Same payload as `HARNESS_RESULT`.

Fictional isolated sqlite only (Garden Path / App Project / Personal / Tunnel N). Not live user records.

## Isolation (held)

| Probe | Before | After |
|---|---|---|
| live qs pid | `294362` `quickshell -n -p /usr/share/omarchy/shell` | `294362` unchanged |
| `shell.json` | `2cb5507fdc8fa3d8cb062244fdce57ddbf7f8280a9b1ce1640a8dcba333270eb` | same |
| live `Panel.qml` | `32f61045d6c17faacd964de79205fcf27c1fd3fd3f381ad95dc5239b3329f18d` | same |
| live store | `c74d7275d66c678a3e30c70f3fb2e1fbb74f2542274ef2c44986330d52ff9d84` | same |
| live plugin git | `9cdf2a75f34e197e2f0eea1327561959fbd27739` | same |
| live plugin present | yes | yes (not removed, not rewritten) |
| empty override plugin dir | empty | still empty |

No Wayland display passed to harness qs. No enable/disable/restart.

## `iconComponent`

Repo stub `tests/native/harness/qs/Ui/BarIconButton.qml` does **not** declare `iconComponent`.

That stub is **not** what ran. `run-isolated.sh` overlays packaged `/usr/share/omarchy/shell/Ui`, then restores only KeyboardPanel/Panel stubs. Packaged `BarIconButton.qml` declares `property Component iconComponent: null` and a Loader `sourceComponent`. Overlay SHA `bae9894d021655105b67d4ae7dec734bcd36ebf3b17a4aaef2c462e0cfa0c874`. Harness was not widened.

## Screenshots (fictional isolated panel only)

Remote originals: `/tmp/breadcrumb-final-native-20260909224642/evidence/screenshots/`
Local copies: `/tmp/breadcrumb-final-native-20260909224642/evidence/screenshots/`

| Tag | Size | SHA-256 |
|---|---|---|
| screenshot-compact.png | 380×277 | `e7fe0f4d12db8e921e83ce6f4bef9dfa9c84c452841bfbc0dcb310af9c6bd3b2` |
| screenshot-expanded.png | 720×520 | `6625abad51af1086d5d22752a35c6fedb8bd6031987546ed5173ed96a2c19ebe` |
| screenshot-narrow.png | 360×520 | `5b77f7b64dd4fff0eadca95bddcb5e972059079d689548c5b82db85ad4f4d840` |
| screenshot-many-activities.png | 720×520 | `4eb98ce7c431f458930a1cc0a6dc38de706da29aa631640ac0d0371ff0bd3d24` |
| screenshot-narrow-save.png | 360×520 | `498e4078ba5c7dd803aa5d77f2dd8b2dc4e7907f05cbbc73dbd209af684a932d` |
| screenshot-narrow-links.png | 360×520 | `afa745842c809e3ae5232797d66a12d4aa4fbbe906df6f77535318f667691249` |
| screenshot-narrow-history.png | 360×520 | `40613027612d0189844d51171dd99816657ad3921aa234e5ed5ad691ac7db145` |

Traversal: save / links-open / history-restore all `contained=true` without assigned `contentY`. Catcher: `popupOpen=true`, `editorChanged=true`.

## Limitations (not claimed by this run)

- Component test, not full omarchy-shell host integration.
- KeyboardPanel and host Panel are stubs: no WlrLayershell, no live IPC, no live Escape / popout-switch / exclusive-zone proof.
- Not dual-monitor placement or live theme swap.
- Not live bar / installed SSH workflow.
- `LIVE_PLUGIN_DIR` env override was required because the live plugin now exists; the runner’s “live plugin dir still has no tbassss.breadcrumb” line refers to the empty override dir, not the real install.
- `ui-results.json` recovered from stdout rather than the `BREADCRUMB_RESULTS` path.
- Isolated native does not supersede owner live acceptance already recorded on issue #8, and does not authorize merge, public visibility, tag, or directory submission.

## Evidence paths

- Remote: `/tmp/breadcrumb-final-native-20260909224642/` (archive, harness, evidence, empty-plugins)
- Isolated qs HOME/XDG: `/tmp/breadcrumb-native-Dq5j`
- Local disposable: `/tmp/breadcrumb-final-native-20260909224642/`
- This report: `/tmp/breadcrumb-final-native-report.md`

Repository `/home/hermes/omarchy-breadcrumb` was not modified.
