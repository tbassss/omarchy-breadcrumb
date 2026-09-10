# Contributing

## Workflow

1. Read the product spec and current issue. Agree on one coherent behavior and acceptance criteria.
2. Work in a focused branch. Add a failing behavioral test, implement the behavior, then run focused and relevant broader checks.
3. Open a PR with the problem, change, verification, risks, and limitations. Link its issue. Do not manufacture retroactive history or claim unrun tests.
4. Obtain risk-relevant review and owner merge approval. Verify the merged result and issue state.

Small documentation changes need proportionate link, content, and diff checks rather than invented application tests. The initial repository bootstrap establishes the first commit; subsequent changes use branches and PRs.

## Evidence and privacy

Use fictional checkpoints and screenshots. Do not commit credentials, real user state, health data, or private session transcripts. Attribute AI assistance honestly; owner usability approval is not a claim that the owner audited code security.

## Current verification

The first five implementation slices (issues #3, #4, #5, #6, and #7) add a native plugin layout, a Python 3 stdlib SQLite store, a public stdin-JSON command, and Compact/Expanded polish against installed Omarchy controls. Issue #8 first-candidate live journeys and independent source review are historical (see labeled docs/RELEASE_PREP.md). Public v0.1.0 shipped; delete/unarchive later merged on main. GitHub release 0.2.0 and directory listing remain separate approvals. Run `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`, `python3 -m py_compile bin/breadcrumb-store bin/breadcrumb tests/*.py`, Markdown link checks, issue-template frontmatter, and `git diff --check`. Store tests cover persistence, CAS, activity isolation, archive, unarchive, archived permanent delete, archive-generation CAS, history restore, drafts, acknowledged-base CAS, generation tombstones, revision conflicts, overlapping UI session scheduling, faults, permissions, and safe links including missing-file Open. Public command tests cover malformed/oversized input, required expected revision, same-revision concurrent writers, interrupted publication, receipt/readback, draft preservation, and read-without-create. Plugin tests are source contracts, not Omarchy runtime evidence. Independent fake-launcher tests cover argv Process success, nonzero, and start-failure without opening real apps. Isolated native Compact/Expanded save/reopen/Panel-recreate plus create A/B, switch, archive access, history restore, compact picker resync, durable draft recover, compact published+draft indicator, recreate old-base save, Keep-editing retry, overlapping autosave/navigation, explicit Save behind queued autosave, obsolete discard protection, public-CLI open-panel plus closed-panel refresh, compact bounded glance, catcher-routed keyboard Expand, height-capped scroll, fake Process Open outcomes, missing-file error, narrow 360×520 keyboard traversal to Save/History/Links with viewport containment, hanging fake launcher 8s timeout+reap, packaged Dropdown popupOpen key routing, editor `j` text mutation, isolated screenshots, and isolated native archived-delete confirmation (Compact must not display or execute delete; collapse cancels pending confirm; keyboard default Cancel; stale publish; fallback; last-entity empty) and isolated native unarchive (Compact must not show Unarchive; one-click restore preserves selection/checkpoint/draft; delete hidden after unarchive; pending confirm invalidated; keyboard Unarchive) is `tests/native/` on the-cave (component test with packaged qs.Ui controls; KeyboardPanel/host Panel stubbed and cap-aware; not live desktop acceptance). See `docs/IMPLEMENTATION.md`, `docs/DELETE_ARCHIVED_ACTIVITY.md`, and `docs/UNARCHIVE_ACTIVITY.md`.

## Installable source tree

Omarchy installs this repository as the plugin payload. Development-only, auto-discovered agent instruction files (such as `AGENTS.md` or `CLAUDE.md`) do not belong anywhere in this tree. Contributors can keep private agent configuration outside the checkout and installed plugin directory; renaming or nesting the same instruction file is not a packaging fix. Ordinary contributor documentation and the explicit command API documentation remain available here.

`tests/test_distribution.py` checks known instruction filenames and directories recursively. It is a bounded regression guard, not a complete prompt-injection detector or security audit. See [the packaging fix record](docs/PACKAGING_SECURITY.md).

## Release boundary

The repository is public (`tbassss/omarchy-breadcrumb`). License is MIT (owner-approved). GitHub release publication, git tags, and plugins.omarchy.org listing submission remain distinct approvals. Before calling a new version shipped: audit source and history for sensitive data, document limitations, and check the official directory's current rules. See `CHANGELOG.md` and labeled historical records in `docs/RELEASE_PREP.md`.
