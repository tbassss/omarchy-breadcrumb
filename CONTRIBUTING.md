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

This repository currently contains documentation and templates only. No plugin tests or CI checks exist yet. Check Markdown links, issue-template frontmatter, and `git diff --check`. Add executable tests with the first implementation slice; passing documentation checks does not prove plugin behavior.

## Release boundary

Keep the repository private until explicit approval. Before release: confirm license, audit source and history for sensitive data, verify clean installation/removal and supported environments, document limitations, and check the official directory's current rules. Public visibility, release publication, and directory submission are distinct approvals.
