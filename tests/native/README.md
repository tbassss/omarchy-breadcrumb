# Isolated native harness (issues #3, #4, and #5)

Component test: real `Panel.qml` + `/usr/bin/qs` + Qt offscreen. Not full omarchy-shell host integration. Not a live install.

## What it asserts

Retained from #3:

1. UI-driven create + save of a fictional checkpoint.
2. Same-instance close/open keeps the published `current.*`.
3. A genuine in-memory draft (`dirty=true` with different editor text) survives `refresh()` / open — get must not broadly reset dirty.
4. Destroy + recreate the Panel (Loader `active=false` then `true`). Published `current.*` reloads **and** editor fields hydrate (`editSummary === current.summary`, dirty is false) when no durable draft exists.

Retained from #4, still on the actual Panel instance:

5. Create activity B (`App Project`), save a distinct checkpoint, switch A/B with matching editor readback.
6. Recreate while a selected activity has state; editor hydrates.
7. Archive B and still read its checkpoint; switch back to A without mixing histories.
8. Restore A's first checkpoint as a **new** revision; original checkpoint id remains.
9. Compact `activityPicker.selectCurrent` (assignment-before-`changed`, matching installed Dropdown) stays aligned with the current activity after completed picker switch and a later JS activity change.

Added for #5:

10. `saveDraft()` persists editor text without appending history. Compact still shows the published checkpoint and `hasDraft` / "Unsaved draft".
11. Destroy + recreate recovers the durable draft into the editor; published `current.*` is unchanged; history count is unchanged; recovered hydration does not bump `draftRevision`.
12. Activity switch and create persist the current draft first (no in-memory Save/Discard/Cancel prompt). Returning to A recovers the draft. Create while a draft exists must not discard A's durable draft.
13. An external `publish` through the store CLI (internal test seam, not the public agent CLI) while a draft exists: Save checkpoint shows `conflictPrompt`, keeps the draft, and does not overwrite the newer publication. Deliberate resolution publishes the draft against the observed current revision.

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
