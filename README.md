# Breadcrumb

A save point for your work — an Omarchy plugin for activity-based checkpoints, written by you or your agent.

**In development. There is no released or live-installed version yet.**

The repository now includes implementation slices through issue #7: a native
bar-widget plugin, a local SQLite store, a documented public command, and
Compact/Expanded polish against installed Omarchy controls. It is not enabled
on a desktop and not a release candidate.

## Planned experience

- Named activities with a current status, next step, optional context and links.
- Persistent checkpoints, recoverable drafts, and per-activity history.
- Manual updates and an agent-independent local command interface.
- Local storage; no cloud account, embedded AI, or activity surveillance.

## Project records

- [Approved product spec](docs/PRODUCT_SPEC.md)
- [Issue #6 command interface](docs/COMMAND.md)
- [Issue #7 implementation notes](docs/IMPLEMENTATION.md)
- [Contributing](CONTRIBUTING.md)
- [Agent instructions](AGENTS.md)

## Local checks

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
python3 -m py_compile bin/breadcrumb-store bin/breadcrumb tests/*.py
git diff --check
```

Native Omarchy Compact/Expanded polish, keyboard, geometry, and isolated
screenshots are a component test on the-cave (`tests/native/`). Passing Python
tests is not live desktop acceptance. See `docs/IMPLEMENTATION.md`.

## Privacy and release

Keep real checkpoints, credentials, and personal screenshots out of this repository, including while private. Public visibility, releases, and directory submission require owner approval. MIT is the proposed license, pending confirmation before publication; no license grant is made yet.
