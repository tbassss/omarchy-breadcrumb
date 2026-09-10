# Breadcrumb public command (v1)

Local, documented agent/script interface for issue #6. It identifies activities,
reads the published checkpoint, and publishes a new checkpoint against a
**required** expected revision. Receipts and errors are JSON on stdout.

This is not the UI store seam (`bin/breadcrumb-store`). Agents must use
`bin/breadcrumb`. There is no server, queue, cloud account, or credential store.
Author is attribution, not authentication.

## Invocation

Prefer **stdin JSON**. Do not interpolate note text into a shell command line.

```bash
python3 bin/breadcrumb list
python3 bin/breadcrumb read   < payload.json
python3 bin/breadcrumb publish < payload.json
```

The operation may also be the JSON `op` field. If both argv and JSON supply
`op`, they must match. `list` with empty stdin is a valid v1 list.

`breadcrumb-store` remains the plugin persistence process. It may accept argv
JSON because Quickshell `Process.command` is a string list, not a shell. That
path is not the public agent interface.

## Versioned envelope

Every non-empty input object must include `"v": 1`. Receipts and errors echo
`"v": 1` and `"op"`.

Unknown `v`, unknown `op`, non-object JSON, and trailing garbage are
`invalid_request`. Extra keys that would imply overwrite, draft consume, or
draft discard are rejected (`invalid_request`).

### Bounds

| Limit | Value |
|---|---|
| Stdin bytes | 65536. Larger input is `invalid_request` without parsing the body. |
| `activity_id` | Canonical UUID text |
| `summary` | 1–500 Unicode characters, plain text |
| `next_step` | 1–500, required unless `state` is `done` |
| `context` | 0–8000 |
| `author` | 1–200, attribution only |
| `state` | `ready` \| `in_progress` \| `waiting` \| `done` |
| Link `label` | 1–200 |
| Link `target` | 1–2000; `web` is `http`/`https` only; `file`/`folder` is an absolute path |
| Link `kind` | `web` \| `file` \| `folder` |
| Links per publish | same store cap as the UI |

No control characters in text fields. Link targets are not interpolated into
shell.

## Operations

### `list` — identify activities by stable ID

Input:

```json
{"v": 1, "op": "list", "include_archived": false}
```

`include_archived` is optional and defaults to `false`.

Success:

```json
{
  "ok": true,
  "v": 1,
  "op": "list",
  "activities": [
    {
      "id": "11111111-1111-4111-8111-111111111111",
      "name": "Study session",
      "created_at": "2026-04-01T12:00:00Z",
      "archived_at": null,
      "revision": 3,
      "summary": "Finished the routing lesson"
    }
  ]
}
```

`id` is the stable activity UUID. `revision` is the published checkpoint
revision (`0` and `summary` null when none exist). This command does **not**
create a data directory, database, activity, or selected-activity preference.
A missing store is success with `"activities": []`.

### `read` — current published state

Input:

```json
{"v": 1, "op": "read", "activity_id": "11111111-1111-4111-8111-111111111111"}
```

`activity_id` is **required**. There is no implicit “currently selected”
activity for agents. Unknown id is `validation` / unknown activity, not a
created row.

Success:

```json
{
  "ok": true,
  "v": 1,
  "op": "read",
  "activity": {"id": "...", "name": "...", "created_at": "...", "archived_at": null},
  "revision": 3,
  "current": {
    "id": "...",
    "activity_id": "...",
    "revision": 3,
    "summary": "...",
    "next_step": "...",
    "context": "...",
    "state": "in_progress",
    "author": "Agent",
    "saved_at": "...",
    "links": []
  },
  "has_live_draft": true
}
```

`current` is `null` and `revision` is `0` when the activity exists but has no
checkpoint. `has_live_draft` is a boolean hint only; draft **payload** is not
part of the public interface. Read does not create activities, does not set
the UI selected activity, and does not create a missing store (that is
unknown activity).

### `publish` — required expected revision

Input:

```json
{
  "v": 1,
  "op": "publish",
  "activity_id": "11111111-1111-4111-8111-111111111111",
  "expected_revision": 3,
  "summary": "Practice set is underway",
  "next_step": "Recheck the last two answers",
  "context": "Fictional course notes only.",
  "state": "in_progress",
  "author": "Agent",
  "links": [{"label": "Spec", "kind": "web", "target": "https://example.com/spec"}]
}
```

`expected_revision` is **required** (integer, including `0`). Missing,
non-integer, or string values are `validation`. There is no overwrite flag,
no “force”, and no omitted-revision default.

This command calls the **same** validated `publish` transaction as the UI
(`BEGIN IMMEDIATE`, published revision CAS, crash-safe current + history).
It never sends `consume_draft_revision`. A live manual draft and its
`base_revision` stay on disk. Concurrent writers with the same
`expected_revision` yield one success and one `stale_revision`; the loser
does not append history.

Success receipt:

```json
{
  "ok": true,
  "v": 1,
  "op": "publish",
  "activity_id": "...",
  "revision": 4,
  "checkpoint_id": "...",
  "saved_at": "...",
  "current": { "...same object as a subsequent read..." },
  "has_live_draft": true
}
```

The receipt’s `current` / `revision` / `checkpoint_id` must match a following
`read` of the same activity.

## Errors

Always one JSON object on stdout, non-zero exit:

```json
{"ok": false, "v": 1, "op": "publish", "error": "stale_revision", "message": "...", "current_revision": 4, "expected_revision": 3}
```

| `error` | Exit | When |
|---|---|---|
| `invalid_request` | 2 | Malformed / oversized / wrong `v` / unknown `op` / forbidden keys |
| `validation` | 3 | Types, bounds, unknown activity, missing required fields |
| `stale_revision` | 4 | `expected_revision` is not the current published revision |
| `permission` | 5 | Data directory or database not user-writable |
| `io` | 6 | Interrupted or I/O failure; no success receipt |
| `schema` | 7 | Unsupported store schema |

An interrupted publish does not report `ok: true` and does not leave a partial
history row.

## Not in this interface

- Creating, renaming, or archiving activities
- Deleting activities
- Saving, reading payload of, consuming, or discarding drafts
- Implicit overwrite, `force`, or omitted `expected_revision`
- Changing the UI selected activity or view
- Network listeners, queues, or retries

## Panel refresh

The plugin watches the local store with a bounded timer while the panel is
open and reloads published `current` without a shell restart. A closed panel
reloads on reopen (`onOpenedChanged`). Refresh updates published fields and
conflict UI; it must not clobber newer in-memory editor text, a live draft, or
in-flight autosave state. Manual drafts stay on their acknowledged base.

## SSH (optional, existing host path)

Use the already-authorized SSH account and feed JSON on stdin so note text
never lands in the remote argv:

```bash
ssh -o BatchMode=yes tbasss@the-cave \
  'python3 /path/to/omarchy-breadcrumb/bin/breadcrumb publish' \
  < payload.json
```

If the host is unreachable, SSH fails and Breadcrumb does **not** queue the
update. Treat that as “not delivered”, not as a successful publish.

A real SSH test of a **live installed** plugin requires the owner installation gate
(issue #8). Isolated `/tmp` `HOME`/`XDG` offscreen component tests
are not that gate and must not be described as a live installed SSH workflow.

After an approved live install the command path is
`~/.config/omarchy/plugins/tbassss.breadcrumb/bin/breadcrumb`. Data remains
in `${XDG_DATA_HOME:-$HOME/.local/share}/breadcrumb/` and is not removed
by `omarchy plugin remove`.

## Out of scope

Live install, restart, merge, public visibility, listing submission, and
release publication remain unapproved. See `docs/RELEASE_PREP.md`.
