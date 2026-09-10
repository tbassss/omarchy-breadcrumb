# Changelog

## 0.2.0 — unpublished until a release action

This tree sets root `manifest.json` `version` to `0.2.0`. That is **not** a GitHub release, git tag, or [plugins.omarchy.org](https://plugins.omarchy.org/) listing. Those remain separate owner-approved actions. Do not announce 0.2.0 as shipped until they happen.

Public `v0.1.0` remains the last tagged GitHub release.

### Added

- **Unarchive** an archived activity from Expanded: one click, no confirmation. The same stable activity returns to the active list with its current checkpoint, history, links, and any saved or in-memory draft. Unarchive does not append a checkpoint and is not history Restore. Compact does not show Unarchive.
- **Permanent delete** of an archived activity after a confirmation that names that activity and warns that its checkpoints, history, links, and draft will be removed. Cancel is a no-op. Delete is hidden for an active activity. Compact cannot display or complete delete. No bulk delete. Not exposed on the public `bin/breadcrumb` command.

### Safety and schema

- Additive column `activities.archive_generation INTEGER NOT NULL DEFAULT 0`. `schema_meta.version` stays `1`.
- New stores create the column; existing stores `ALTER TABLE` inside the same crash-safe `BEGIN IMMEDIATE` `init_schema` transaction.
- Each successful archive of an active activity increments generation. Unarchive retains generation (does not reset it).
- Delete confirmation freezes `expected_archive_generation` with the other CAS tokens (`expected_archived_at`, revision, draft, name). A later delete with old tokens after unarchive or same-second re-archive is rejected and does not mutate.

### Migration

Opening this store migrates an existing `schema_meta.version = 1` database in place by adding the generation column when missing. Pre-existing columns and rows are not rewritten by that additive step. Historical live-acceptance records document a compared migration on the owner's host; this changelog does not restate those private paths.

### Rollback caution

- Replacing this plugin with a store binary that does **not** check `expected_archive_generation` reintroduces same-second `archived_at` ABA: an old delete confirmation can still delete after unarchive / re-archive in the same second.
- `schema_meta.version` stays `1` so an older binary can still open the file. That mixed-binary residual is intentional and unsafe for delete consent.
- Do **not** restore an older SQLite backup over a newer database. That can undo later checkpoints and can restore deliberately deleted activities. Rolling back plugin files is separate from restoring a database and needs explicit approval and a safety reassessment.

### Documentation in this tree

User-facing README and this changelog describe public-main behavior (v0.1.0 plus merged delete / unarchive). First-candidate private/gated wording in older review receipts is labeled historical and is not current install status.

### Runtime note

This documentation pass does not change `Panel.qml`, `Model.js`, `bin/breadcrumb-store`, or `bin/breadcrumb`. Those bytes match public main `cf5b9a76038dbe44379f3ca4295f2e3b4f787677`.
