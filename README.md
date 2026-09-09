# Breadcrumb

A save point for your work — an Omarchy plugin for activity-based checkpoints, written by you or your agent.

**In development. There is no released or live-installed version yet.**

The repository now includes the first three implementation slices (issues #3, #4, and #5): a native bar-widget plugin and a local SQLite store so named activities can save, switch, archive, restore, and recover unpublished drafts. It is not enabled on a desktop, not an agent CLI, and not a release candidate.

## Planned experience

- Named activities with a current status, next step, optional context and links.
- Persistent checkpoints, recoverable drafts, and per-activity history.
- Manual updates and an agent-independent local command interface.
- Local storage; no cloud account, embedded AI, or activity surveillance.

## Project records

- [Approved product spec](docs/PRODUCT_SPEC.md)
- [Issue #5 implementation notes](docs/IMPLEMENTATION.md)
- [Contributing](CONTRIBUTING.md)
- [Agent instructions](AGENTS.md)

## Local checks

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
python3 -m py_compile bin/breadcrumb-store tests/*.py
git diff --check
```

Native Omarchy save/reopen/activity-switch/history-restore/draft-recovery is an isolated component test on the-cave (`tests/native/`). Passing Python tests is not live desktop acceptance. See `docs/IMPLEMENTATION.md`.

## Privacy and release

Keep real checkpoints, credentials, and personal screenshots out of this repository, including while private. Public visibility, releases, and directory submission require owner approval. MIT is the proposed license, pending confirmation before publication; no license grant is made yet.
