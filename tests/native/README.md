# Isolated native harness (issues #3, #4, #5, #6, and #7)

Component test: real `Panel.qml` + `/usr/bin/qs` + Qt offscreen + packaged
`qs.Ui`/`qs.Commons` controls copied from `/usr/share/omarchy/shell`.
KeyboardPanel and host Panel stay stubs (WlrLayershell / live IPC).
Not full omarchy-shell host integration. Not a live install.

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
9. Compact activity picker assignment-then-`changed` (matching installed Dropdown `selectCurrent`) stays aligned with the current activity after completed picker switch and a later JS activity change.

Added for #5:

10. `saveDraft()` persists editor text without appending history. Compact still shows the published checkpoint and `hasDraft` / "Unsaved draft".
11. Destroy + recreate recovers the durable draft into the editor; published `current.*` is unchanged; history count is unchanged; recovered hydration does not bump `draftRevision`.
12. Activity switch and create persist the current draft first (no in-memory Save/Discard/Cancel prompt). Returning to A recovers the draft. Create while a draft exists must not discard A's durable draft.
13. An external `publish` through the store CLI (internal test seam, not the public agent CLI) while a draft exists: recreate, then ordinary Save checkpoint shows `conflictPrompt`, keeps the draft, and does not overwrite the newer publication. Keep editing then ordinary Save still conflicts. Deliberate resolution publishes the draft against the observed current revision.
14. Same-tick delayed `saveDraft` + newer keystrokes + `switchActivity`: newer text is persisted or navigation stays deferred with visible state; v1 ack must not drop v2.
15. Explicit `saveCheckpoint` queued behind an in-flight autosave is not dropped when another `saveDraft` is issued.
16. `discardDraft` overlapping later keystrokes must not clobber the editor.

Added for #6:

17. While the panel stays **open**, a public `bin/breadcrumb publish` (stdin JSON, required expected revision) refreshes published `current` without Loader recreate or shell restart. In-memory editor text and dirty stay. Conflict UI is shown. Draft base is not adopted from the new revision.
18. With the panel **closed**, a public publish appears on reopen. In-memory draft is not clobbered. Conflict UI remains.

Added for #7:

19. First-use view is Compact. Recreate after Expand remembers Expanded.
20. Long published summary stays a bounded Compact glance (`maximumLineCount` geometry); Expanded keeps the full text.
21. Packaged `qs.Ui.Button` has no `enabled` property; Expand is `focusable: (!root.busy)` and Return toggles the view through packaged `PanelKeyCatcher` (not Expand `forceActiveFocus` bypass).
22. Missing file Open shows a visible error and does not produce `open_argv`. Safe `https` Open records `xdg-open -- <url>` with `BREADCRUMB_NO_OPEN=1` (no real launch). Fake argv Process tests cover success, nonzero, and start-failure with visible `lastError`. A hanging fake launcher must hit the production 8s `openTimeout`, show the error, and reap the child; no real links are opened.
23. Narrow expanded width stacks the activity sidebar. Many activities stay inside a capped Flickable. The main expanded column is a height-capped `panelScroller`; stub inflated 1393/1820px screenshots are not acceptance. At actual `360×520`, Tab/Down/Up/j must traverse to real Save, History Restore, and Links Open controls, keep each in the visible viewport, and activate a safe action. Record `contentY`/geometry/screenshots after that traversal; assigning `contentY` or merely proving overflow is not enough.
24. Packaged `PanelKeyCatcher` + packaged Dropdown: `popupOpen` blocks the catcher so Down/Up/Return/Tab route to the dropdown. Editor `j` must modify field text, not merely leave the view expanded.
25. Isolated `grabToImage` screenshots of the fictional harness panel only.

These are native evidence. A Python source-contract pass is not a substitute. They are not live bar / real KeyboardPanel layer-shell acceptance. They are not a live installed SSH workflow.

## Archived delete confirmation

`tests/native/run-delete-isolated.sh` plus `harness/delete-shell.qml`
is the in-repo deletion component test. Same isolation as above:
disposable HOME/XDG, offscreen Qt, packaged overlay, stub
KeyboardPanel/host Panel. `LIVE_PLUGIN_DIR` defaults to an empty
disposable directory so the runner absence guard is not the live
plugin path; real live plugin/shell/pid hashes are snapshotted
independently. That is not proof the live plugin is absent.

It asserts Compact has no delete request, collapse cancels pending
confirmation, Compact cannot display or execute confirm, re-expand
does not resurrect confirm, keyboard default is Cancel (Return is a
no-op cancel), named-target warning, Cancel no-op, switch clears
confirm, stale publish fail-closed, selection fallback, and
last-entity empty state.

```bash
ARCHIVE=/path/to/candidate.tar \
CANDIDATE_SHA=<git sha> \
EVIDENCE_DIR=/tmp/breadcrumb-delete-native-XXXX \
HARNESS_SRC=/path/to/tests/native/harness \
  ./tests/native/run-delete-isolated.sh
```

RED against `a00bb04` must fail on Compact confirmation after collapse.
GREEN is the repaired candidate.

## Run on the-cave only

Isolated `HOME`/`XDG`, `QT_QPA_PLATFORM=offscreen`, unique `XDG_RUNTIME_DIR`. No Wayland, no live plugin enable, no `shell.json` mutation, no shell restart. The runner overlays packaged Omarchy controls and keeps KeyboardPanel/Panel stubs.

```bash
ARCHIVE=/path/to/candidate.tar \
CANDIDATE_SHA=<git sha> \
EVIDENCE_DIR=/tmp/breadcrumb-evidence-XXXX \
HARNESS_SRC=/path/to/tests/native/harness \
  ./tests/native/run-isolated.sh
```

`ARCHIVE` is a `git archive` of the candidate plugin tree. The script copies it into disposable `/tmp/breadcrumb-native-*`.

Results and API notes: [`docs/IMPLEMENTATION.md`](../../docs/IMPLEMENTATION.md).
