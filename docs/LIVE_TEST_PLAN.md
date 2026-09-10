# Live install / rollback plan (owner approval required)

**Historical first-candidate live-install plan (issue #8).** Later public
v0.1.0 and merged delete/unarchive live installs supersede the “plugin
absent / not installed” snapshot below. Do not treat this as current host
state or as v0.2.0 release authorization. The gated steps and rollback
commands are preserved as written.

Do **not** execute this plan until the owner explicitly approves live
installation. This document is read-only preparation. It does not authorize
plugin enable, `shell.json` mutation, theme change, or `omarchy-restart-shell`.

Target: The Cave (`tbasss@the-cave`), Omarchy `4.0.3-1`, Quickshell `0.3.1`.
Plugin id: `tbassss.breadcrumb`. Default bar section: `right`.

## Why this is gated

Spec journeys 2, 3, 9, and 10 require a real bar, possible shell restart,
live theme/monitor placement, and install/remove that preserves checkpoints.
Isolated `/tmp` `HOME`/`XDG` offscreen tests do not satisfy those journeys.

## Pre-change snapshot (record, do not mutate)

Record these **before** any install. Values observed 2026-09-09 during
ungated prep (must be re-read immediately before an approved run):

| Item | Observed during prep |
|---|---|
| Live qs | pid `1494`, `quickshell -n -p /usr/share/omarchy/shell` |
| `~/.config/omarchy/shell.json` | sha256 `469bfd9b5c8a29ff3e5e8f45a09a66729eaf6a4e4b42462cf26fc99f4102eaee` |
| `~/.config/omarchy/plugins/tbassss.breadcrumb` | **ABSENT** |
| `~/.local/share/breadcrumb` | **ABSENT** (no live user data yet) |
| Bar right | `io.github.tyrichards.tray`, `tbasss.proton-vpn`, `omarchy.tailscale`, `omarchy.network`, `omarchy.audio`, `omarchy.microphone`, `omarchy.monitor`, `omarchy.power` |

Commands (read-only):

```bash
ssh -o BatchMode=yes tbasss@the-cave 'pgrep -af "quickshell -n -p /usr/share/omarchy/shell"; sha256sum ~/.config/omarchy/shell.json; test -e ~/.config/omarchy/plugins/tbassss.breadcrumb && echo PRESENT || echo ABSENT; test -d ~/.local/share/breadcrumb && echo DATA_PRESENT || echo DATA_ABSENT; python3 -c "import json; d=json.load(open(\"/home/tbasss/.config/omarchy/shell.json\")); print(d[\"bar\"][\"layout\"])"'
```

Copy `shell.json` to a rollback file owned by tbasss, e.g.
`/tmp/breadcrumb-rc-rollback/shell.json`. Do not write that copy into the
source repository.

## Approved install (smallest reversible path)

Use a **git checkout** so `omarchy plugin remove` deletes the folder instead
of leaving a `.bak` (non-git installs are moved aside, not removed).

1. Re-record the snapshot above. Abort if `tbassss.breadcrumb` is already present.
2. Transfer the frozen candidate (git archive or `git clone` of the agreed SHA)
   to a disposable path under `/tmp`, not into live config yet.
3. `git clone` that tree into
   `/home/tbasss/.config/omarchy/plugins/tbassss.breadcrumb`.
   Confirm `manifest.json` id is `tbassss.breadcrumb`.
4. `omarchy plugin validate /home/tbasss/.config/omarchy/plugins/tbassss.breadcrumb`
   Must exit 0. Plugin must still be **disabled**.
5. Owner: `omarchy plugin enable tbassss.breadcrumb --section right`
   This mutates `shell.json` bar layout. Do not pass `--enable` during add
   unless the owner wants enable in the same step.
6. Confirm the widget appears on the live bar. If it does not,
   **stop and ask** before `omarchy-restart-shell`.
7. Owner dogfood with **fictional** checkpoints only (Study / App Project /
   Personal stand-ins). Walk spec journeys 1–10 including manual use without
   an agent, optional `bin/breadcrumb` publish over existing SSH, shell
   restart reopen, theme/monitor if the owner wants those checks.
8. Record owner usability notes. Do not treat that as a security audit.

Public command after install:

```bash
python3 /home/tbasss/.config/omarchy/plugins/tbassss.breadcrumb/bin/breadcrumb list
```

Data after first save: `/home/tbasss/.local/share/breadcrumb/breadcrumb.sqlite`.

## Approved rollback

1. `omarchy plugin disable tbassss.breadcrumb`
2. `omarchy plugin remove tbassss.breadcrumb --yes`
   Host script: disable if enabled, `rm -rf` git checkouts, otherwise move to
   `~/.config/omarchy/plugins/.tbassss.breadcrumb.bak.<timestamp>`, then
   `omarchy-shell shell rescanPlugins`.
3. Confirm plugin dir ABSENT.
4. Compare `shell.json` sha to the snapshot. If it still lists
   `tbassss.breadcrumb` or bar order drifted, restore the snapshot copy
   (that is a config write; confirm with the owner) and rescan.
5. Confirm `/home/tbasss/.local/share/breadcrumb` **still exists** if the
   owner created checkpoints. Removal must not delete that directory.
6. Confirm live qs still healthy. Restart only if the owner approves and the
   bar is stuck.
7. Do not delete the XDG database unless the owner asks.

## What this plan must not do

- No credential changes, no network server, no public visibility, no listing
  submission, no tag/release push.
- No custom Tray or package-managed shell patches.
- No nested live desktop / Wayland screenshot of the user's session during
  ungated prep. Those belong to the approved dogfood window.
