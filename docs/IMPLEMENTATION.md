# Implementation notes for issue #3

First persistent manual checkpoint. Not a release, not installed, not an agent CLI.

## Supported Omarchy APIs inspected (read-only on the-cave)

- Plugin contract: `manifest.json` at plugin root, `schemaVersion: 1`, `kinds` + `entryPoints`, no `omarchy.*` id, no symlinks. Validated by `omarchy plugin validate` / `PluginRegistry.qml`.
- Bar widget host: `qs.Ui.Panel` + `BarIconButton` + `KeyboardPanel` + `PanelKeyCatcher`, theme via `qs.Commons` (`Color`, `Style`).
- Subprocess: `Quickshell.Io.Process` with `command` as a string list; `StdioCollector { waitForEnd: true }`. JSON payload is an argv element, not a shell string. Network panel writes secrets with `stdinEnabled`/`write()`; this slice uses argv JSON because checkpoint payloads are small and Process does not expose close-stdin.
- Open links: `Quickshell.execDetached(open_argv)` after the store returns `["xdg-open", "--", target]`. No `bash -c` interpolation.
- Do not depend on `io.github.tyrichards.tray` or other custom shell patches.
- Toolchain on the-cave: `/usr/bin/python3` 3.14, `/usr/bin/qs` Quickshell 0.3.1, `omarchy plugin validate`.

## Storage

- Python 3 stdlib `sqlite3` only.
- Default directory: `$XDG_DATA_HOME/breadcrumb` or `~/.local/share/breadcrumb` (0700). Override: `BREADCRUMB_DATA_DIR`.
- Database `breadcrumb.sqlite` (0600), schema version 1.
- Rollback journal (`PRAGMA journal_mode=DELETE`) and `PRAGMA synchronous=FULL`.
- Stable activity UUIDs. Checkpoints are append-only; current is `MAX(revision)`.
- Publication uses `BEGIN IMMEDIATE` plus `expected_revision` CAS. Stale writers fail without writing.
- `bin/breadcrumb-store` is the UI persistence seam. It is not the public agent command from issue #6.

## Out of scope (#4–#8)

Activity switching/rename/archive, history browser, disk draft recovery, public agent CLI, glance polish, live install/release.

## Native save/reopen evidence (not run)

Python tests and QML source contracts are not native Omarchy evidence. Isolated native harness, requiring coordinator approval:

```bash
# On the-cave, disposable HOME only. Do not write ~/.config/omarchy of the live user.
HARNESS=$(mktemp -d /tmp/breadcrumb-native-XXXX)
export HOME="$HARNESS/home"
export BREADCRUMB_DATA_DIR="$HARNESS/data"
mkdir -p "$HOME/.config/omarchy/plugins"
# Copy this repo (or plugin files) to:
#   $HOME/.config/omarchy/plugins/tbassss.breadcrumb
omarchy plugin validate "$HOME/.config/omarchy/plugins/tbassss.breadcrumb"
# Then a nested omarchy-shell/qs session that loads only this bar-widget,
# with no live plugin enable, no shell.json mutation of the real user,
# no service restart. Precise host command depends on how omarchy-shell
# discovers plugins from $HOME; confirm before running.
```

Do not treat this document as permission to install or restart anything.
