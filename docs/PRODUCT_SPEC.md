# Breadcrumb — Product Spec

Status: Product behavior approved by Tyler. Implementation slices #3–#7 shipped in public v0.1.0. Archived-activity permanent deletion and unarchive are merged on public main and included in local unpublished v0.2.0.
Stage: Public repository. GitHub release 0.2.0 and directory listing are unpublished until a separate release action. First-candidate live/review receipts in RELEASE_PREP.md are historical, not current install status.
Mainframe Build Tracker: None.

## Purpose

Breadcrumb is an Omarchy plugin for resuming named activities. It displays the latest deliberately saved checkpoint and its history, whether written by the user or by their existing agent.

A checkpoint answers: Where are we? What should I do next? What do I need to know to resume?

This is a personal handoff surface, not a replacement for GitHub issues, study notes, or a project backlog. It shows the last recorded state, not independently verified live project status.

## Intended users

- People switching among study, coding, and personal activities.
- People who want an agent to leave concise handoffs after work sessions.
- People without agents who want the same functionality manually.

WGU, Coach, and Life are Tyler's examples, not built-in categories. Public documentation, fixtures, and screenshots must use fictional data.

## First-release experience

### Activity navigation

Users can create and rename activities, switch among them, and archive finished activities without erasing checkpoints. An archived activity can be returned to the active list with one Unarchive action; that is reversible and does not require confirmation. Unarchive keeps the same stable activity, current checkpoint, history, links, and any saved or in-memory draft. It does not append a checkpoint and is not history Restore. An archived activity can be permanently deleted only after a confirmation that names that activity and warns that its checkpoints, history, links, and draft will be removed. Cancel leaves the activity unchanged. Delete is hidden for an active activity. There is no bulk delete. A compact activity selector and current checkpoint must remain usable with long names and more activities than fit across one row. Approved layout: one interface with Compact and Expanded views sharing the same activity and checkpoint state. Default to Compact on first use and remember the last chosen view. Compact uses an activity picker and displays the status summary, next step, timestamp, and reported author. Expanded uses an activity sidebar and provides context, links, editing, and history. Editing and history are implemented once, in Expanded. Expand/Collapse must preserve the selected activity and manual draft; collapsing an editor shows the published checkpoint, not an unsaved draft. On narrow screens, adapt the layout without losing the distinction between glance and editing views.

### Current checkpoint

Each activity has one current published checkpoint containing:

- A short status summary (where things stand).
- A next step (what to do next).
- Optional longer context.
- Optional labeled web, file, or folder links.
- A simple state: ready, in progress, waiting, or done. Exact labels can be refined in the prototype.
- Save timestamp and reported author (human or tool).

Status and next step are visible without opening another app. Longer details, links, and history are available within the panel. Show an honest empty state when no checkpoint exists. A completion state may omit a next step.

Links open only on explicit action. Do not execute embedded shell commands or arbitrary URL schemes. Missing files and launch failures must produce understandable feedback.

### Drafts versus checkpoints

Manual typing preserves a local draft, but does not create history on every keystroke. An explicit Save checkpoint action publishes a meaningful handoff. Closing the panel or restarting must not silently discard the draft.

If an agent updates an activity while a human is drafting, preserve both the published update and human draft. Show the conflict and require deliberate resolution before replacing the newer checkpoint. Never silently apply last-writer-wins behavior.

### History

Every successful checkpoint publication creates a dated history entry for that activity. Earlier entries remain readable. Bringing an older checkpoint forward creates a new checkpoint; it does not rewrite intervening history. Creating, renaming, switching, or archiving an activity must not mix histories.

For the first release, there is no automatic history expiration or silent deletion. History views load a bounded portion at a time. After explicit owner approval, a confirmed permanent delete is available only for an archived activity and removes that activity's checkpoints, history, links, and draft. Cancel is a no-op. There is no bulk delete and no public command delete. Document where local data lives and preserve it on plugin removal.

### Agent and script updates

Provide a documented local command interface. It supports identifying activities, reading current state, and publishing a checkpoint with an expected current revision. It validates input, rejects stale writes clearly, and returns a machine-readable receipt or error. Human UI and command updates share the same persistence and conflict rules.

Use stable activity identifiers rather than display names as write identity. Reported author is attribution supplied by the writer, not authenticated proof of who wrote it.

The plugin refreshes after a successful external update without a shell restart. No need to keep the panel open during the update.

Any agent capable of invoking the command can integrate. No bundled model, agent runtime, provider credential, or required AI subscription. Integration instructions explain how to add checkpoint updates to an agent's session-completion workflow; installation alone does not configure agents.

For Tyler, use his existing authorized SSH route to invoke the local command on The Cave. SSH belongs to the user's setup, not a network service shipped by Breadcrumb. If the host is offline, report that no update was delivered. Automatic queuing and catch-up are deferred.

## Persistence, privacy, and reliability

- Local-first user data, outside the source repository; no network requests for checkpoint storage.
- Crash-safe publication: an interrupted write must not corrupt current state or history or produce a false success receipt.
- Serialize concurrent writers and check expected revisions within the protected write operation.
- Protect local data with appropriate user-only permissions. Do not imply the Omarchy plugin is OS-sandboxed or that author labels are authentication.
- Treat all text as plain content; notes must not execute code or load remote images.
- Keep draft and published state distinguishable; do not replace a valid checkpoint with empty content after a read failure.
- Provide visible save/load errors and a recoverable draft where possible.
- Uninstall leaves user data in place and documents its location.

## Acceptance journeys

1. Create Study, App Project, and Personal activities with fictional checkpoints. Switching among them preserves each next step and its history independently.
2. Save a checkpoint, close and reopen the panel, and restart the shell during approved testing. The checkpoint is unchanged.
3. Type an unsaved draft and reopen after a restart. The draft is recoverable and history has not gained a checkpoint.
4. Publish a replacement checkpoint. The old checkpoint remains readable; restoring it appends a new publication without erasing newer history.
5. Publish through the local command while the panel is open and while closed. Reopening/refreshing shows the saved revision without a shell restart; the receipt agrees with readback.
6. Start a human draft, publish a command update, then try saving the draft. Both contents survive, and the user sees a conflict instead of silently overwriting the command update.
7. Submit two updates against the same revision. Only one can succeed; the other receives a conflict with no partial checkpoint or orphaned history.
8. Exercise malformed input, markup, command-like links, missing files, storage errors, and interrupted writes. No unintended execution, false success, or loss of the previously committed state.
9. Verify keyboard operation, long content, empty states, theme changes, popup placement, and both monitors on a supported Omarchy build. Do not claim compatibility with configurations not tested.
10. Install from the documented source layout, use it manually without an agent, and remove it without deleting user checkpoints.
11. Archive an activity, confirm permanent delete by name, and verify its checkpoints, history, links, and draft are gone while a neighbor activity is unchanged. Cancel leaves the archived activity intact.
12. Archive an activity, Unarchive it in one click, and verify the same stable activity returns to the active list with its current checkpoint, history, links, and draft intact. Unarchive does not confirm, does not append a checkpoint, and does not resurrect a deleted activity.

## Non-goals for the first release

Cloud accounts/sync, embedded AI, automatic GitHub polling, task assignment, calendar/reminder systems, screenshots, clipboard watching, activity surveillance, automatic app/window restoration, remote servers, offline-delivery queues, mobile clients, and automatic checkpoint deletion.

No dependency on Tyler's custom Tray repair. Use supported Omarchy plugin interfaces; do not patch package-managed shell files as an installation prerequisite.

## Historical delivery sequence after spec approval

The numbered plan below is the original private-development sequence. The repository is now public and v0.1.0 shipped. Remaining publication, listing, and live-install items stay separate approvals; do not read “preserve private visibility” as current status.

1. Create the proposed private repository tbassss/omarchy-breadcrumb after checking availability and authenticated permissions. Explicitly preserve private visibility. Add development README, this approved spec, contributor/agent rules, issue and PR templates, and source-data exclusions. MIT license, owner-approved 2026-09-09; see LICENSE. Public visibility remains a separate approval.
2. Prepare a small visual prototype to settle the activity selector and at-a-glance checkpoint hierarchy before substantial UI implementation.
3. Translate the approved behavior into bounded GitHub issues and an implementation plan. GitHub issues are the execution backlog; no Kanban or competing backlog requested.
4. Build vertical slices: one persistent manual checkpoint; multiple activities/history; agent command and draft-conflict handling; release usability and packaging. Use RED-to-GREEN checks and real receipts. Persistence and concurrent update semantics require independent risk-focused review before accepting the candidate.
5. With separate approval, install a verified candidate on The Cave for real use. Preserve existing shortcuts, plugins, and shell configuration. Ask Tyler for usability feedback, not a code-security endorsement.
6. Prepare public release: source/history privacy audit, fictional screenshots, license, supported versions, clean-install verification, limitations, release notes, and official directory requirements. Making public, publishing a release, and submitting a listing are separate explicitly approved external actions.

## Approval and remaining design decisions

Tyler approved this product spec, including archive behavior, no automatic history expiration, and later explicit approval of archived-only permanent deletion (not Trash). The compact status vocabulary is an approved starting point. Visual layout will be shown in the prototype. Implementation schema, language boundaries, module paths, and exact CLI syntax belong to the subsequent technical plan, not choices Tyler needs to make now.
