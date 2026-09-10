# Unarchive live acceptance

**Historical live-acceptance record.** Unarchive later merged to public
main (`#16`). “Public v0.1.0 is unchanged; this feature remains on a local
branch” was true of that pass, not current git state. Owner observations,
migration comparison, and rollback caution are preserved as written.

Owner confirmed the archived activity returned to the active list with its checkpoint, history and draft intact on installed `66f3bef1069958e02a66c680d6674c8a72dbdc7e` (runtime `800130540c574f1df209d1eb12b02cf65a162f4b`). This is hands-on usability evidence, not a human security audit.

Approved installation and shell restart: plugin validation passed, restart exited 0, subsequent IPC ping returned ok. Composer compared all pre-existing columns/rows of every database table against the SQLite online backup after migration: unchanged. The archive_generation column was present and shell.json unchanged. Initial diagnostic SSH quoting failed before execution; corrected read-only probe supplied the actual comparison.

Private Cave rollback backup: ~/.local/state/breadcrumb-unarchive-install/20260909-205436 (prior plugin, shell.json, SQLite online backup). No backup or private runtime records are included here. Do not automatically restore an old database over newer records. Reverting to an old store loses archive-generation protection, as documented in UNARCHIVE_CLOSURE_REVIEW.md; rollback requires explicit approval and safety reassessment.

Independent closure passed with 100 Python tests and authenticated native delete/unarchive evidence. Owner approval of live behavior does not authorize pushing, merging, or publishing a release. Public v0.1.0 is unchanged; this feature remains on a local branch pending those gates.

AI assistance: Hermes performed implementation coordination, verification and documentation; independent leaf reviews are identified in the closure report. Tyler owns product decisions and live usability acceptance.
