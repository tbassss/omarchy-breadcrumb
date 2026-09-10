# Breadcrumb unarchive ABA repair — bounded closure

Verdict: **PASS**

Scope: independent closure of the same-second `archived_at` ABA finding only, plus touched migration/compatibility and regressions. Unrelated noncritical nits not reopened. No repo edits. No live plugin/config/data writes, installs, restarts, or publish.

## Identity

| Item | Value |
|---|---|
| Candidate | `800130540c574f1df209d1eb12b02cf65a162f4b` |
| Parent (overturned PASS) | `25e627239b97d1ab53751fe305a2d1dd02d68db4` |
| Branch | `feat/unarchive-activity` |
| Worktree | `/home/hermes/omarchy-breadcrumb` clean (`git status --porcelain` empty) at HEAD = candidate |
| Ancestor | `git merge-base --is-ancestor 25e6272 8001305` exit 0 |
| Subject | `fix: retain archive generation across unarchive` |
| `SCHEMA_VERSION` | `1` (unchanged) |

HEAD runtime/harness SHA-256 (also the native-tested bytes):

| File | SHA-256 |
|---|---|
| `Panel.qml` | `df45cc350a7ffa5490246919361886c98b1ab3b7d1af47289c49826b4febdc99` |
| `bin/breadcrumb-store` | `b0fc0b77c82f71fb85644ce05a30081ebff8933a6d52bae3c43419c75ef80504` |
| `bin/breadcrumb` | `e39e8b17c4717ee4aa49511bfce4122b77ec32f65ca571a671cf7f61245711af` |
| `Model.js` | `7839f3957043896192ecba5ba29ee99b591dd14b33fd483384e30801ccb60549` |
| `tests/native/harness/delete-shell.qml` | `456f1a2dc01176a671dd42eea52601d3cbf2f59baeaf2ad6a12989b0fedd3835` |
| `tests/native/harness/unarchive-shell.qml` | `f7e5ba2bca7da44c01e46bce306050687354da3ada8b6df1edccd061ba75a43c` |

`git archive --format=tar HEAD` SHA-256: `24aeab8e017355df3b9e2ecbfe11e85bedeb56ca3154a4df6c0f1070bf1d4745`
Native worktree tar (Cave): `556504df322aa155cdcf46e056f3d7207830ba9793777cf835aed4b9bd307d8e`

Tar vs HEAD: runtime, tests, harness, `CONTRIBUTING.md`, `docs/COMMAND.md`, `docs/IMPLEMENTATION.md` are byte-identical. Only `docs/UNARCHIVE_ACTIVITY.md` and `docs/DELETE_ARCHIVED_ACTIVITY.md` differ (receipts landed after the native run). Allowed docs-only successor of the tested runtime/harness.

## Prior finding — closed

`/tmp/breadcrumb-unarchive-review.md` PASS was overturned for: same-second unarchive/re-archive with forced identical `archived_at` still accepted an old delete consent (`ok: true`).

This candidate:

- Adds `activities.archive_generation INTEGER NOT NULL DEFAULT 0` without bumping `schema_meta.version`.
- Increments generation on each successful archive of an active row (`UPDATE … archive_generation = archive_generation + 1 WHERE id = ? AND archived_at IS NULL`).
- Unarchive sets `archived_at = NULL` only; generation is retained.
- Delete requires `expected_archive_generation` (missing → `validation`, no write). Mismatch → `stale_revision`, extra `current_archive_generation`.
- UI freeze includes `expected_archive_generation` from the observed activity; confirm sends the frozen payload.

Independent probes on this HEAD (not writer claims):

| Probe | Result |
|---|---|
| create 0 → archive 1 → unarchive retains 1 / `archived_at` null → re-archive 2 → already-archived no-op stays 2 | PASS |
| Old UI payload omitting `expected_archive_generation` | `validation` / “expected_archive_generation is required”, row survives |
| Same-clock retained second-instance (`test_second_instance_confirmation_deletes_after_first_instance_stale`) | PASS (in 100-test suite) |
| Same-second + clock-rollback ABA (`test_same_second_unarchive_rearchive_rejects_old_delete_bytes`, `test_wall_clock_rollback_does_not_reuse_delete_consent`) | PASS |
| Additive v1 migration without row/checkpoint loss (`test_existing_v1_db_gains_archive_generation_without_losing_rows`) | PASS |
| Concurrent first migration: legacy v1 DB, 60 mixed get/archive/unarchive/delete processes | column present, version 1, Keep checkpoint intact, exactly one delete success, Gone gone, unarchive cannot resurrect |
| Parent `25e6272` store + missing generation after same-second cycle | parent `ok: true` (ABA residual confirmed); new store `stale_revision` / rc 4 |

## Tests run here

```
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
Ran 100 tests in 26.530s  OK
python3 -m py_compile bin/breadcrumb-store bin/breadcrumb tests/*.py  OK
git diff --check 25e6272..8001305  OK
```

Includes the required same-clock retained second-instance confirm fail-closed path.

## Native authentication (Cave, not re-run)

Surviving isolated evidence; runtime/harness hashes equal HEAD. Component tests (packaged qs.Ui overlay; host Panel/KeyboardPanel stubbed). `LIVE_PLUGIN_DIR` was empty disposable; live plugin/shell independently hashed.

| Run | Path | Result |
|---|---|---|
| Delete | `/tmp/breadcrumb-delete-gen-UgdH` | `ok=true` step 33, `staleCycleRejected=true`, `frozenArchiveGeneration=1`, lastError “This activity is no longer in the archived state you confirmed.” `HARNESS_OK`. `qs_rc=0`. Results recovered from stdout (`ui-results.missing` present; 10495 bytes). |
| Unarchive | `/tmp/breadcrumb-unarchive-gen-9r91` | `ok=true` step 18, compact had neither Unarchive nor Delete, selection/revision/draft preserved, delete hidden, confirm cleared, keyboard Unarchive present+activated, neighbor kept. `HARNESS_OK`. `qs_rc=0`. Recovered stdout 4370 bytes. SQLite: Gone `archived_at` null, revision 1, live draft, Keep intact, selected=Gone. |

Live before/after (both runs, still current at closure): qs pid `584804`, `shell.json` `2bc54c753a5a529b02409e17c093640558341597aa38721cfd55eb97b168360f`, live plugin hash list unchanged (99 lines). Overlay: `bariconbutton_iconComponent=1`, `button_declares_enabled=0`. Omarchy 4.0.3-1, Quickshell 0.3.1. Classification: component test, not live bar / WlrLayershell.

Native was not re-run: existing Cave artifacts authenticate to this commit’s runtime/harness. Isolated only; live plugin not written.

## Compatibility (realistic)

- **New store + old UI omitting `expected_archive_generation`:** fail-closed (`validation`). Evidenced.
- **New store + new UI:** generation CAS holds across same-second / clock-rollback unarchive/re-archive. Evidenced (Python + native delete step 33).
- **Rollback to `25e6272` store (no generation guard):** same-second `archived_at` ABA returns. Evidenced with parent binary against a migrated DB. Documented in `docs/UNARCHIVE_ACTIVITY.md` / `docs/DELETE_ARCHIVED_ACTIVITY.md`. `schema_meta.version` stays 1 so an old binary can still open the DB; that is an intentional mixed-binary residual, not a new critical defect in this candidate.
- Public `list`/`read` omit `archive_generation` (tested). Public CLI still rejects unarchive/delete.
- Public v0.1.0 is not this candidate; this tree is local-only.

## Not reopened

- `tests/draft_session.py` initializes `archive_generation = 0` and does not copy it from snapshots. Test double only; production freeze is `Panel.qml` `root.activity.archive_generation`. Native freeze was 1.
- Native results-file absence with stdout recovery (pre-existing harness behavior; same asserts applied).
- Component-test limits (no live bar / WlrLayershell / Escape / monitor placement).
- Unrelated nits from prior reviews.

## Residual (accepted, documented)

Rolling the store binary back to a build that does not check `expected_archive_generation` reintroduces same-second `archived_at` ABA. Do not mix this store with `25e6272` or earlier delete binaries on the same data dir.

## Reviewer actions

- Read AGENTS.md, CONTRIBUTING.md, `docs/UNARCHIVE_ACTIVITY.md`, `docs/DELETE_ARCHIVED_ACTIVITY.md`, prior `/tmp/breadcrumb-unarchive-review.md`.
- No checkout mutation, no live plugin/config/data writes, no install/restart/publish.
- Isolated `/tmp` Python probes only; Cave evidence read-only.
