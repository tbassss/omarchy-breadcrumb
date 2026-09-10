# Bread icon acceptance

**Historical icon-import record** for first-candidate `Panel.qml`. Later
public v0.1.0 and merged delete/unarchive changed other runtime bytes;
this document’s hashes describe the icon-import SHA only.

## Problem and change

The original disk glyph communicated saving but not Breadcrumb's identity. The owner requested bitten bread, then accepted a polished rounded outline with two crumbs after inspecting it on the live bar. This change imports those exact approved Panel.qml bytes; storage, keyboard/pointer actions and checkpoint behavior are unchanged. The Canvas uses the supported BarIconButton iconComponent slot and foreground/active colors rather than a fixed theme color.

## Actual verification

- New source-contract test failed against the disk version, then passed against the imported icon. This is a source contract, not a rendering test.
- Full Python suite: 70 tests passed.
- git diff --check passed.
- Imported Panel.qml SHA-256: `32f61045d6c17faacd964de79205fcf27c1fd3fd3f381ad95dc5239b3329f18d`, equal to the captured owner-approved installed file.
- Installed Omarchy plugin validation passed. After separately approved supported shell restart, IPC ping returned ok and a bar-only screenshot showed the outlined bread. Owner accepted its appearance. Private screenshots are not stored in this repository.

## Limitations and remaining work

Live rescan did not visually replace the old icon; a separately approved shell restart did. Duplicate-handler warnings were observed but causality was not established. Theme repaint and size handlers are covered as source contracts, not a newly exercised live theme/monitor matrix. Full isolated native suite was not rerun for this icon-only import; earlier native evidence predates it. Removal/reinstall of runtime candidate `9cdf2a75f34e197e2f0eea1327561959fbd27739` subsequently passed: exact logical database equality and owner-confirmed activities/history/draft recovery (issue #8). This is not merge, public-release or directory-submission approval.

## Live rollback

On Cave, the original disk Panel.qml is backed up at `~/.local/state/breadcrumb-icon-trial/20260909-151742/Panel.qml`. The intermediate solid bread is at `~/.local/state/breadcrumb-icon-trial/20260909-152104/Panel.qml`. Restoring a selected file to the installed plugin reverts only the icon trial; do not touch the user data directory. A shell restart requires separate approval.

Implementation and verification were AI-assisted through Hermes; owner approval concerns appearance, not an independent security audit.
