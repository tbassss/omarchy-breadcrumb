# Isolated native harness (issues #3 and #4)

Component test: real `Panel.qml` + `/usr/bin/qs` + Qt offscreen. Not full omarchy-shell host integration. Not a live install.

## What it asserts

Retained from #3:

1. UI-driven create + save of a fictional checkpoint.
2. Same-instance close/open keeps the published `current.*`.
3. A genuine in-memory draft (`dirty=true` with different editor text) survives `refresh()` / open — get must not broadly reset dirty.
4. Destroy + recreate the Panel (Loader `active=false` then `true`). Published `current.*` reloads **and** editor fields hydrate (`editSummary === current.summary`, dirty is false).

Added for #4, still on the actual Panel instance:

5. Create activity B (`App Project`), save a distinct checkpoint, switch A/B with matching editor readback.
6. A dirty editor blocks switch with Save/Discard/Cancel; cancel keeps A and the in-memory draft.
7. Recreate while B is selected; B's editor hydrates.
8. Archive B and still read its checkpoint; switch back to A without mixing histories.
9. Restore A's first checkpoint as a **new** revision; original checkpoint id remains.
10. Compact `activityPicker.selectCurrent` (assignment-before-`changed`, matching installed Dropdown) stays aligned with the current activity after dirty Cancel, failed stale save-switch, completed picker switch, and a later JS activity change.
11. `createActivity` while dirty refuses with a visible message, stays on A, and keeps the in-memory draft.

These are native evidence. A Python source-contract pass is not a substitute. They are not live bar / real KeyboardPanel layer-shell acceptance.

## Run on the-cave only

Isolated `HOME`/`XDG`, `QT_QPA_PLATFORM=offscreen`, unique `XDG_RUNTIME_DIR`. No Wayland, no live plugin enable, no `shell.json` mutation, no shell restart.

```bash
ARCHIVE=/path/to/candidate.tar \
CANDIDATE_SHA=<git sha> \
EVIDENCE_DIR=/tmp/breadcrumb-evidence-XXXX \
HARNESS_SRC=/path/to/tests/native/harness \
  ./tests/native/run-isolated.sh
```

`ARCHIVE` is a `git archive` of the candidate plugin tree. The script copies it into disposable `/tmp/breadcrumb-native-*`.

Results and API notes: [`docs/IMPLEMENTATION.md`](../../docs/IMPLEMENTATION.md).
