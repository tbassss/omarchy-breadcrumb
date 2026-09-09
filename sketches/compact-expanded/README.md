# Compact / Expanded — selected design direction

Owner approved two views of one interface. Open index.html: Compact is the default, Expand reveals the activity sidebar and the shared editor/history. Both use one in-memory checkpoint model. A draft survives collapse/expand within the page. Compact shows published content, not an unsaved draft. The view preference uses browser localStorage when available, with a safe fallback when unavailable.

## Verification

Real browser: Compact and Expanded screenshots inspected. Changed the activity using the compact picker, expanded, edited a next step, collapsed, confirmed compact still showed the published value, expanded, confirmed the exact draft survived, and saved successfully. Previous variant checks cover in-memory history. git diff --check required before commit.

Browser harness blocked the localhost test origin, so tests used a data URL. Persistence of the view preference across reload was NOT verified because data URLs do not provide usable localStorage. Native QML, real persistence, conflict handling, SSH, and activity management remain unimplemented. Fictional data only; checkpoint edits reset on reload.

The original compact-tabs and activity-sidebar sketches remain as design exploration history, not separate shipping modes.
