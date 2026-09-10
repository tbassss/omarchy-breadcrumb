# Breadcrumb final candidate review

**Historical first-candidate source review.** Contemporaneous “private repo”
and “0.1.0 not shipped” claims below are not current status. Public v0.1.0
later shipped; delete/unarchive later merged. Review identity, hashes, test
counts, and defect notes are preserved as written.

Independent, read-only, AI-assisted review. No merge, publish, listing, live mutation, or repo edit. Persistence/CAS/draft spec is not reopened: store and public CLI bytes are unchanged from the already-reviewed base, and this delta contains no new persistence defect.

## Identity

| Field | Value |
|---|---|
| Exact candidate | `9cdf2a75f34e197e2f0eea1327561959fbd27739` |
| Branch | `release/first-candidate` (ahead 2 of `origin/main`) |
| Base | `80eb9b6752dd59e30aa34cb6aaf499f470845438` (ancestor) |
| Repo | `tbassss/omarchy-breadcrumb` **private**; issue [#8](https://github.com/tbassss/omarchy-breadcrumb/issues/8) **OPEN** |
| HEAD before | exact match, worktree clean |
| HEAD after | exact match, worktree git-clean |

`bin/breadcrumb-store` sha256 at HEAD equals base: `c74d7275d66c678a3e30c70f3fb2e1fbb74f2542274ef2c44986330d52ff9d84`.

`Panel.qml` sha256 at HEAD: `32f61045d6c17faacd964de79205fcf27c1fd3fd3f381ad95dc5239b3329f18d` (matches `docs/ICON_ACCEPTANCE.md` and issue #8 icon-import comment). Base `Panel.qml` remains `21449ed07d5280beee5dd35a58b241b82773105da5c185a1f9638e673ac6d2e1`.

Runtime code change vs base: **`Panel.qml` only** (outlined bread `iconComponent`). Store, public CLI, and `manifest.json` bytes are unchanged. Tests added/updated: `tests/test_bread_icon.py`, `tests/test_plugin_contract.py` MIT/LICENSE assertions.

## Tests this review ran

In `/home/hermes/omarchy-breadcrumb` with `PYTHONDONTWRITEBYTECODE=1`:

```
python3 -m unittest discover -s tests -v
python3 -m py_compile bin/breadcrumb-store bin/breadcrumb tests/*.py
git diff --check 80eb9b67..HEAD
```

Result: **70 tests OK** (17.081s). `py_compile` exit 0. `git diff --check` clean. `python3 -m py_compile` wrote gitignored `tests/__pycache__`; git porcelain stayed empty.

Isolated native `tests/native/` was **not** rerun here (icon-only delta; `ICON_ACCEPTANCE.md` already records that earlier native evidence predates the icon). No live host commands.

## Delta vs `80eb9b67`

Two commits:

1. `5960272` docs/LICENSE/fictional screenshots/release-prep materials; plugin runtime unchanged at that commit.
2. `9cdf2a7` owner-approved outlined bread bar icon in `Panel.qml` plus source-contract test and `docs/ICON_ACCEPTANCE.md`.

LICENSE is standard MIT, copyright 2026 tbassss, matching `manifest.json` `"license": "MIT"`. Tracked screenshots are isolated fictional harness captures (`Fictional Garden Path`, lantern inventory, Tunnel N). No SQLite, `.env`, credentials, or runtime-data in HEAD. Markdown links in the delta resolve locally; GitHub issue #8 and plugins.omarchy.org URLs are external references only.

Click/middle-click actions on `BarIconButton` are unchanged (`refresh()` / `root.toggle()`). Icon uses supported `iconComponent`, theme `foreground`/`activeColor`, and separate crumb paths. Owner live-accepted appearance on issue #8.

## Evidence sufficiency (issue #8 comments authoritative)

Owner-confirmed live on The Cave for candidate `9cdf2a75…` (and the preceding live install of `5960272` that this SHA replaced):

- Manual save + same-session panel reopen
- Agent SSH publish with draft preservation and conflict notice
- Explicit Save-draft-as-checkpoint conflict resolution
- History listing of the three Test checkpoints
- History restore appends a new revision
- Multi-activity isolation (Test / Test Two)
- Archive is non-destructive
- Draft recovery after approved `omarchy-restart-shell` (IPC ok; owner saw editor recover)
- Bread icon live-accepted after approved restart
- Disable/remove/reinstall of **this SHA**; exact logical DB equality; owner confirmed activities, history, and unfinished draft after reinstall

These cover PRODUCT_SPEC journeys 1 (create/switch), 2 (save/reopen + restart for draft), 3 (draft restart), 4 (history restore), 5 (command publish + readback), 6 (draft+command conflict + deliberate resolution), and 10 (install/manual use/remove preserves data) at live-bar level for the tested fictional activities.

Not claimed as live-complete: dual-monitor, live theme swap, KeyboardPanel exclusive-zone / Escape / popout-switch, Keep-editing vs Overwrite (only Save-as-checkpoint was live), concurrent same-revision live writers, missing-file Open on the live bar, unreachable-host, Compact-only published reopen after restart as a distinct owner check. Isolated native still classified component-test, and was not rerun after the icon import.

## Concrete defects

No new persistence, CAS, draft, history, or public-CLI defect in this delta (store/CLI hashes identical to the reviewed base).

No icon runtime defect contradicting owner live acceptance.

**Records defect in the candidate tree:** `docs/RELEASE_PREP.md` still identifies plugin bytes as `80eb9b67`, quotes the **disk-icon** `Panel.qml` hash, and says the prep commit “does not change plugin runtime behavior.” HEAD **does** change `Panel.qml`. Using that document as install identity would restore the rejected disk glyph. `README.md` / `docs/PRODUCT_SPEC.md` / `docs/COMMAND.md` / `docs/LIVE_TEST_PLAN.md` still speak as if the tree is not live-installed and dogfood has not happened; that is false relative to later issue #8 comments (some of those tests landed after `5960272`, and the icon commit did not reconcile the prep docs). `docs/ICON_ACCEPTANCE.md` still says removal/reinstall “remains paused”; issue #8 later closed that live journey on this SHA.

These are documentation/identity defects, not plugin-behavior bugs. They matter because RELEASE_PREP is the in-tree candidate-identity record.

Pre-existing, not in this delta, not reopened as a persistence issue: `tests/test_activities.py` uses the display name `WGU Course Notes` while PRODUCT_SPEC requires fictional fixtures. Not a secret or runtime payload.

## Remaining acceptance gaps (not defects in this SHA)

- In-tree prep docs not reconciled with HEAD identity or with issue #8 live evidence.
- Isolated native suite not rerun after icon import.
- Live theme / dual-monitor / KeyboardPanel placement details unproven.
- Alternate conflict UI paths (Keep editing / Overwrite) not owner-confirmed live.
- Public visibility, GitHub release/tag, plugins.omarchy.org listing, merge to `main`, and announcing `0.1.0` as shipped: **not approved**. Repo remains private.
- Issue #8 still OPEN. Last owner-visible comment: removal/reinstall closed the tested data-retention journey; remaining acceptance and frozen-candidate review still to be reconciled. This review is that frozen-source pass, not close/merge permission.
- Owner usability approval is not a security audit (already stated in-tree).

## Verdict

**PASS as frozen source candidate `9cdf2a75f34e197e2f0eea1327561959fbd27739`.** No new runtime or persistence defect. Local 70-test suite green. Live issue #8 evidence is sufficient for the listed journeys, including icon and remove/reinstall.

**FAIL for issue #8 close, merge, publish, or listing.** Reconcile in-tree candidate identity (especially `docs/RELEASE_PREP.md`) with this SHA before treating docs as the freeze record; remaining live/usability and separate owner approvals still block release.

Do not install `80eb9b67` over this SHA.
