# Checkpoint layout comparison

Status: Awaiting owner layout choice. Disposable HTML sketches, not production plugin code.

- [Compact tabs](compact-tabs/index.html): narrower popup; less room for many activities.
- [Activity sidebar](activity-sidebar/index.html): wider popup, visible activity states; recommended for multiple ongoing activities.

Open either HTML file in a browser. Both are standalone with no external dependencies. All content is fictional; edits reset on reload. History is illustrative and in-memory. Native theme integration, persistence, draft recovery, conflict resolution, restore actions, activity management, and SSH are not implemented.

## Verification receipts

Both files loaded in a real browser. Screenshots inspected: readable layouts without overlapping content at the desktop viewport tested. Browser-driven actions verified activity switching, editing/saving a next step, and opening history containing the previous next step for each layout. These are prototype smoke checks, not production acceptance tests or Omarchy compatibility evidence. Compact layout requires more vertical space. No live desktop configuration changed.

## Decision sought

Choose the activity navigation and checkpoint hierarchy before building the native interface. Colors are illustrative; the production plugin should follow supported Omarchy theme tokens.
