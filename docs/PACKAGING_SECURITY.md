# Agent-instruction packaging correction

## Problem

Marketplace submission [#6057](https://github.com/omacom/omarchy-plugin-marketplace/issues/6057#issuecomment-5620695344) was blocked because root `AGENTS.md` ships with the installable repository. Tools that discover agent instruction files could load development guidance from an installed plugin. Automated structural/security-baseline checks passing earlier did not establish that the payload was safe from this concern.

## Change

Remove `AGENTS.md` entirely from the candidate tree; do not relocate or rename its contents within the payload. Existing human contributor documentation remains. Agent-specific operational guidance is maintained outside the distributed project. Add a recursive guard for known agent instruction filenames/directories, including nested and case-variant names.

This is a packaging-only correction against base `20a9f75714397a0a2a549e8be9cd216fdb4be8ae` (published v0.2.0). No changes to Panel.qml, Model.js, bin/breadcrumb-store, bin/breadcrumb, manifest version, or user data. No rewriting Git history or existing release tags.

## Verification

- RED: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_distribution.py -v` ran 3 checks; the payload check failed with exactly `['AGENTS.md']` before removal.
- GREEN: `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v` passed all 104 tests after removal (26.347s).
- This guard checks known paths, not arbitrary malicious instructions. It is not a complete prompt-injection detector or independent security audit.
- Native UI/live install tests were not repeated: no runtime bytes changed and no live actions are authorized by this fix PR.

## Delivery and remaining gates

The fix PR is not a merge, release, deployment or marketplace approval. Main and existing tags remain unchanged until separately authorized. After approved merge, validation must target the new main commit and the reviewer must reassess submission #6057. A release decision is separate; old v0.2.0 archives still contain the old file. Existing installed copies are not modified by this PR.

Rollback of this patch would reintroduce the reported instruction-file exposure; no data migration or runtime rollback is needed. Substantial preparation and testing assistance by Hermes AI; Tyler owns publication/merge/release approvals.
