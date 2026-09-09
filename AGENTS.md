# Breadcrumb agent instructions

Read docs/PRODUCT_SPEC.md and CONTRIBUTING.md before editing. Preserve accepted product behavior; do not quietly expand scope.

Use one writer per candidate, isolated branches, vertical RED-to-GREEN tests, and honest verification receipts. Inspect current supported Omarchy APIs before choosing implementation details. Do not depend on custom shell patches or alter package-managed shell files.

Documentation is part of delivery: explain what changed, why, verification, limitations, and remaining work in the issue/PR. Separate static checks from live UI tests. Pass this contract to delegated workers and verify their artifacts.

Persistence, history, drafts, and concurrent updates are protected invariants requiring risk-focused independent review. Never silently overwrite a newer checkpoint or discard a draft. Use fictional test data. Keep runtime state outside the source repository.

Do not publish, merge, change visibility, install on a live desktop, restart services, change credentials, or submit a listing without the appropriate owner approval. No Kanban or duplicate implementation backlog. A local prototype does not imply release readiness.
