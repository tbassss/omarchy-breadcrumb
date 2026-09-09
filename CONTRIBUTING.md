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

The first implementation slice (issue #3) adds a native plugin layout and a Python 3 stdlib SQLite store. Run `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`, `python3 -m py_compile bin/breadcrumb-store tests/*.py`, Markdown link checks, issue-template frontmatter, and `git diff --check`. Store tests cover persistence, CAS, faults, permissions, and safe links. Plugin tests are source contracts, not Omarchy runtime evidence. Isolated native Compact/Expanded save/reopen/Panel-recreate is `tests/native/` on the-cave (component test, not live desktop acceptance). See `docs/IMPLEMENTATION.md`.

## Release boundary

Keep the repository private until explicit approval. Before release: confirm license, audit source and history for sensitive data, verify clean installation/removal and supported environments, document limitations, and check the official directory's current rules. Public visibility, release publication, and directory submission are distinct approvals.
