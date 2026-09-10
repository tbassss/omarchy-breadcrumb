# Breadcrumb B1 closure recheck

**Historical independent closure record.** Permanent delete later merged to
public main. “No merge, push, install, restart, or public records from
this pass” was true of that pass. Verdict, hashes, and findings are
preserved as written.

Independent read-only recheck of Compact destructive confirmation
(B1), touched keyboard-modal safety, and regressions.

**Verdict: PASS**

B1 is closed on candidate `cd8790f5cc3a74a17e75bf11edf963dbd0b80f15`.
No new critical defect. Do not reopen store/CAS/public-CLI scope.
Composer owns acceptance. No merge, push, install, restart, or
public records from this pass.

## Identity (frozen this recheck)

| Item | Value |
|---|---|
| Candidate | `cd8790f5cc3a74a17e75bf11edf963dbd0b80f15` |
| Subject | `cd8790f fix: keep archived delete confirmation off Compact` |
| Branch | `feat/delete-archived-activity` (local only) |
| Parent BLOCK B1 | `a00bb04dab874568c56dc9f4373d7c5fc5589e29` |
| Work tree | clean |
| Repo | `/home/hermes/omarchy-breadcrumb` |
| HEAD `git archive` SHA-256 | `1ea4a419dcf4adac53183df9a53b6ef43cdd29d26b87a3aa3163cd6f653615a2` |
| Evidence `repaired-cd8790f.tar` | same as HEAD archive |
| Runtime `Panel.qml` | `be4b84ad3a298aa5d96a6ccc3fb3a2e32b9738fdf254bd68a8a363e5dca0948d` |
| `bin/breadcrumb-store` | `4a228c0766dd485aab14dc5b22f8eeda7e68f1407e481e26ed81487a2fefa655` |
| `bin/breadcrumb` | `21ebfda5833c6a223348d912054d150db515e9f93e22b5a70a26ae8578ec2db9` |
| `Model.js` | `7839f3957043896192ecba5ba29ee99b591dd14b33fd483384e30801ccb60549` |
| In-repo `delete-shell.qml` | `b1b0461d7356a93860e55a041451b64d19d50b72488bf76d40ae694069ced780` |
| In-repo `run-delete-isolated.sh` | `d719b9ff191ab94f7b0e05e74c0174c39b9163768b2b9ba4a0feb3648eed1d36` |
| Live plugin Panel | `32f61045d6c17faacd964de79205fcf27c1fd3fd3f381ad95dc5239b3329f18d` (v0.1.0; not this candidate) |
| Live `shell.json` | `2bc54c753a5a529b02409e17c093640558341597aa38721cfd55eb97b168360f` before = after |
| Live qs pid | `294362` before = after (`quickshell -n -p /usr/share/omarchy/shell`) |

Store/CLI/Model bytes are identical to `a00bb04`.
`git diff a00bb04 HEAD -- bin/breadcrumb-store bin/breadcrumb Model.js`
is empty.

## Artifact authentication

RED and GREEN native artifacts in
`/tmp/breadcrumb-delete-repair-evidence` were checked against the
in-repo harness, not accepted from the worker summary.

| Artifact | SHA-256 / result | Authentic? |
|---|---|---|
| RED `old-candidate-a00bb04.tar` / `red/candidate.tar` | `39935c232216febb1b56393ccd6e9022231f3dd33e69ece5cf689f0d3500636d` | yes; equals parent archive; runtime Panel `0858d037…` |
| RED workdir Panel | `0858d0378419c6e29fd6817e9980bbcce884ed19defbafe3e9006c5af1a04de5` | yes |
| GREEN `green2/candidate.tar` / `repaired.tar` | `ab52e4f3697d33441cc0c373574c64963fc525b05b5b40524ada59f756350cc0` | runtime match to HEAD; see docs-only note |
| GREEN workdir Panel / store / CLI / Model | same as HEAD runtime | yes |
| RED+GREEN harness `delete-shell.qml` | `b1b0461d…` = in-repo | yes |
| RED+GREEN runner overlay | packaged `qs.Ui`/`qs.Commons`; stub KeyboardPanel+host Panel | yes (`packaged_overlay=yes`; Button packaged `fda48672…` ≠ repo stub `3725be65…`) |
| RED `ui-results.json` | `ok=false` step 14; recovered from qs stdout (`NO_UI_RESULTS_FILE`) | yes; same bytes in `red/ui-results.json` and `red/logs/ui-results.json` (`81a62bcc…`) |
| GREEN `ui-results.json` | `ok=true` step 33; recovered from qs stdout | yes; same bytes in both copies (`8eb8d13d…`) |
| qs rc | RED 0, GREEN 0; stderr empty; qmlErrors `[]` | yes |

GREEN archive ≠ HEAD archive (`ab52e4f…` vs `1ea4a419…`) because
`docs/DELETE_ARCHIVED_ACTIVITY.md` was written after the native run
and committed in `cd8790f`. Normalized file compare: **only that doc
changed**. Panel, store, CLI, Model, plugin contract, and in-repo
delete harness bytes in GREEN match HEAD. That is a documentation-only
successor of the tested runtime, not a different UI candidate.

This recheck host has no `qs`/`quickshell`. Native was not rerun here.
Classification remains component test (packaged child controls + real
`Panel.qml` + offscreen qs). Not live bar, WlrLayershell, Escape,
popup switching, monitor placement, or theme readability.
`LIVE_PLUGIN_DIR` empty disposable override scopes the runner absence
guard only; live plugin hashes were independently unchanged.

## B1 Compact destructive confirmation — closed

Original BLOCK (`/tmp/breadcrumb-delete-review.md`): after Expand →
confirm → Collapse, Compact still showed the confirmation overlay
(`visible: !!root.deleteConfirm`, no expanded guard, `toggleView`
did not clear, `confirmDeleteArchived` had no expanded check).

Repair in `Panel.qml` (vs `a00bb04`):

1. `toggleView()` clears `deleteConfirm` when next view is compact.
2. Confirm column `visible: !!root.deleteConfirm && root.expanded`.
3. `requestDeleteArchived` and `confirmDeleteArchived` refuse unless
   `root.expanded`.
4. Request button click also requires `root.expanded`.
5. Compact column remains `visible: root.hasActivity && !root.expanded`.
6. Delete request control stays inside `expandedGrid`
   (`visible: root.hasActivity && root.expanded`).

RED (`a00bb04` + **new** in-repo harness):

- `compactHadDelete=false` (Compact with no pending confirm has no
  Delete request).
- After confirm-open → Collapse: `compactConfirmAfterCollapse=true`,
  `collapseCancelledConfirm=false`, `deleteConfirm` still frozen,
  `view=compact`, `expanded=false`, `keyboardTargets=["Expand",""]`.
- Fail string: `compact displayed permanent delete confirmation after collapse`.
- Stops at step 14 (does not reach Compact-execute / keyboard).

GREEN (`cd8790f` runtime + same harness):

| Assert | Value |
|---|---|
| `ok` / `step` | `true` / 33 |
| `compactHadDelete` | false |
| `compactConfirmAfterCollapse` | false |
| `collapseCancelledConfirm` | true |
| `compactConfirmDeleted` | false (direct `confirmDeleteArchived()` while Compact is a no-op) |
| `confirmResurrectedOnReexpand` | false |
| `confirmNamedTarget` | true (exact `"Gone Trail Map"` + checkpoints/history/links/draft) |
| `keyboardDefaultCancel` | true (`keyboardTargets` = `["Cancel","Delete permanently"]`, `cursorIndex=0`) |
| `returnOnConfirmCancelled` | true |
| `cancelLeftActivity` | true |

Screenshots inspected:

- GREEN `compact-after-confirm-open.png`: Compact header **Expand**;
  published glance + Unsaved draft; **no** “Permanently delete…”,
  **no** Cancel/Delete confirmation row.
- GREEN `confirm-open.png`: Expanded **Collapse**; warning names
  Gone Trail Map; buttons **Cancel** then **Delete permanently**.
- GREEN `after-delete.png`: only Keep Lantern Notes; Gone gone; no overlay.
- GREEN `empty-after-last.png`: empty first-use copy; sqlite
  `activities=[]`, `drafts=[]`, pref `view=expanded` only.

Runner post-asserts require all of the Compact/keyboard flags above
before printing `native deletion asserts ok`.

## Keyboard modal safety

In-scope because the repair touched `keyboardTargets` /
`activateKeyboardCursor` / confirm button order.

- While `expanded && deleteConfirm`, `keyboardTargets()` returns only
  Cancel then Delete permanently and returns early (modal).
- `requestDeleteArchived` sets `cursorIndex=0` and reveals Cancel.
- Packaged `PanelKeyCatcher`: Return/Enter and Space both emit
  `activateRequested` → `activateKeyboardCursor`. Default Cancel is a
  no-op cancel; GREEN proved Return.
- Confirm activation still requires `root.expanded`.
- Expanded (no confirm) now includes `deleteRequestButton` at the end
  of the target list (Q3 closed for this candidate).
- Visual row order changed from Delete-then-Cancel (`a00bb04`) to
  Cancel-then-Delete. That matches the keyboard default; not a defect.

## Regressions / store

- Independent `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`:
  **85 tests OK** (19.451s). `py_compile` OK. `git diff --check` clean.
- Plugin source contract asserts expanded guards, collapse-clear,
  Cancel-before-Delete in `keyboardTargets`, and in-repo harness
  fail strings.
- Store/public CLI unchanged by repair; prior 17/17 process probes
  and 84-test store/CAS result on `a00bb04` are not reopened.
- Last-entity native empty state and stale fail-closed path held on
  GREEN (`lastErrorSeen` newer-checkpoint; finding below is residual).

Prior 96-step Compact/Expanded native (`ok=true` step 96) is **not**
in `/tmp/breadcrumb-delete-repair-evidence`. Cannot authenticate that
claim here. Risk to that harness is low: `deleteRequestButton` is
visible only when archived; the modal early-return only runs with
`deleteConfirm`; `toggleView` clear is a no-op when confirm is null.
Nit, not a B1 reopen.

## Residuals (nits; not blocking; not reopened)

From original review, still non-blocking:

- **Q2** GREEN finding `stale_confirm_left_root_revision=1_store_published_after=2`
  (fail-closed until Reload). Spec allows lastError + leave editor.
- **Q1, Q5–Q8, Q10** unchanged. Q3 (keyboard reachability) and Q9
  (in-repo harness) are addressed.
- **Q4** two controls still share label `Delete permanently`; modal
  target list now isolates them while confirm is open.
- Results file written via stdout recovery (`NO_UI_RESULTS_FILE`);
  same success assertions applied.
- RED repair-evidence screenshots include confirm-open only (fail
  before compact grab finished). B1 RED is proven by structured
  `timeoutSnap` + flags, plus the original review compact screenshot.
- Component-test limits (no live Escape/close, no WlrLayershell).
- `createActivity()` still does not itself null `deleteConfirm`.

## Out of scope (unchanged)

No repo edits. No live plugin install/restart. No `shell.json` write.
No push/merge/publication. Live v0.1.0 install remains the prior bread
release.
