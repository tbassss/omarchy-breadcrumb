# Archived deletion: owner live acceptance

Runtime reviewed at `cd8790f5cc3a74a17e75bf11edf963dbd0b80f15`; installed candidate `3e3c3f3511a7e8dc9af818e076b2e1575d3694d9` adds only the closure review record.

## Installation and rollback

Owner approved installation and separately approved shell restart after the old UI remained visible. Installed checkout was clean at the exact candidate, plugin validation passed, shell IPC returned `ok`, and shell configuration was unchanged. Backed up prior plugin, shell configuration, and SQLite via online backup to `~/.local/state/breadcrumb-delete-install/20260909-194751` on the owner's machine. No automatic deletion was performed by the installer.

Rollback should restore the previous plugin only under approval. Do not overwrite the current database automatically: restoring the earlier database would undo subsequent user changes and may restore deliberately deleted activities. These backups are private, outside Git.

## Owner-confirmed live journey

- Delete control appeared on an archived activity in Expanded after restart.
- Named confirmation followed by Cancel preserved the activity and its history.
- On a disposable archived activity, confirmation followed by permanent deletion removed it from the archived list while other activities remained intact.

These are owner-observed UI results, not an independent before/after database audit. Atomic child deletion, stale-confirmation protection, rollback and isolation are covered separately by store probes and native component tests. See DELETE_CLOSURE_REVIEW.md and DELETE_ARCHIVED_ACTIVITY.md for exact evidence and limitations.

## Status

Composer accepts the implementation and tested live journey for proposed PR publication. No branch push, PR, merge, version bump or new release is authorized by this record. v0.1.0 remains the existing release; directory submission remains paused. Hermes provided AI-assisted implementation, verification and review; owner feedback is usability evidence, not a human security audit.
