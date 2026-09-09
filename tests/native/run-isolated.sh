#!/usr/bin/env bash
# Isolated Cave native validation for Breadcrumb issues #3–#7.
# Does NOT install/enable the plugin, restart the live shell, or write live config.
# Packaged qs.Ui/qs.Commons are overlaid from $OMARCHY_PATH/shell. KeyboardPanel
# and host Panel stay stubbed so this does not attach to the compositor.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANDIDATE_SHA="${CANDIDATE_SHA:-}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$PWD}"
HARNESS_SRC="${HARNESS_SRC:-$SCRIPT_DIR/harness}"
ARCHIVE="${ARCHIVE:?ARCHIVE tar of exact candidate required}"

ts() { date -Is; }

LIVE_SHELL_JSON="${LIVE_SHELL_JSON:-/home/tbasss/.config/omarchy/shell.json}"
LIVE_PLUGIN_DIR="${LIVE_PLUGIN_DIR:-/home/tbasss/.config/omarchy/plugins}"

mkdir -p "$EVIDENCE_DIR/logs"

echo "=== begin $(ts) ==="
echo "candidate=${CANDIDATE_SHA:-unknown}"
echo "evidence=$EVIDENCE_DIR"
echo "archive=$ARCHIVE"
echo "harness=$HARNESS_SRC"

LIVE_QS_PID=$(pgrep -n -f 'quickshell -n -p /usr/share/omarchy/shell' || true)
echo "live_qs_pid_before=${LIVE_QS_PID:-none}"
if [[ -n "${LIVE_QS_PID:-}" ]]; then
  tr '\0' '\n' < "/proc/${LIVE_QS_PID}/cmdline" | sed 's/^/  cmdline_part: /'
fi

if [[ -f "$LIVE_SHELL_JSON" ]]; then
  sha256sum "$LIVE_SHELL_JSON" | tee "$EVIDENCE_DIR/logs/live-shell.json.sha256.before"
else
  echo "missing live shell.json" >&2
  exit 1
fi

if [[ -e "$LIVE_PLUGIN_DIR/tbassss.breadcrumb" ]]; then
  echo "REFUSING: live plugin dir already has tbassss.breadcrumb" >&2
  ls -la "$LIVE_PLUGIN_DIR/tbassss.breadcrumb" >&2
  exit 1
fi

WORKDIR=$(mktemp -d /tmp/breadcrumb-native-XXXX)
echo "WORKDIR=$WORKDIR"
mkdir -p \
  "$WORKDIR/runtime" \
  "$WORKDIR/home" \
  "$WORKDIR/config" \
  "$WORKDIR/data" \
  "$WORKDIR/cache" \
  "$WORKDIR/state" \
  "$WORKDIR/breadcrumb-data" \
  "$WORKDIR/plugin" \
  "$WORKDIR/harness" \
  "$WORKDIR/results"
chmod 700 "$WORKDIR/runtime" "$WORKDIR/breadcrumb-data"

tar -xf "$ARCHIVE" -C "$WORKDIR/plugin"
cp -a "$HARNESS_SRC/." "$WORKDIR/harness/"

OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"
OMARCHY_SHELL="${OMARCHY_SHELL:-$OMARCHY_PATH/shell}"
mkdir -p "$EVIDENCE_DIR/screenshots" "$EVIDENCE_DIR/logs"
{
  echo "omarchy_path=$OMARCHY_PATH"
  (pacman -Q omarchy 2>/dev/null || true)
  (/usr/bin/qs --version 2>/dev/null || true)
  echo "python=$(/usr/bin/python3 --version 2>/dev/null || true)"
} | tee "$EVIDENCE_DIR/logs/installed-versions.txt"

if [[ -d "$OMARCHY_SHELL/Commons" && -d "$OMARCHY_SHELL/Ui" ]]; then
  echo "overlaying packaged qs.Commons and qs.Ui from $OMARCHY_SHELL"
  cp -a "$OMARCHY_SHELL/Commons/." "$WORKDIR/harness/qs/Commons/"
  cp -a "$OMARCHY_SHELL/Ui/." "$WORKDIR/harness/qs/Ui/"
  # Keep isolated stubs that would otherwise attach to the live compositor / IPC.
  cp -a "$HARNESS_SRC/qs/Ui/KeyboardPanel.qml" "$WORKDIR/harness/qs/Ui/KeyboardPanel.qml"
  cp -a "$HARNESS_SRC/qs/Ui/Panel.qml" "$WORKDIR/harness/qs/Ui/Panel.qml"
  {
    echo "packaged_overlay=yes"
    echo "omarchy_shell=$OMARCHY_SHELL"
    echo "stubbed=KeyboardPanel,Panel"
    echo "packaged=Button,Dropdown,TextField,BarIconButton,PanelKeyCatcher,Color,Style,Border,Util,and remaining qs.Ui types"
    echo "button_declares_enabled=$(grep -c 'property bool enabled' "$WORKDIR/harness/qs/Ui/Button.qml" || true)"
    echo "dropdown_selectCurrent=$(grep -n 'function selectCurrent' "$WORKDIR/harness/qs/Ui/Dropdown.qml" || true)"
  } | tee "$EVIDENCE_DIR/logs/control-overlay.txt"
else
  echo "WARNING: packaged Omarchy modules missing; using repo facades" | tee "$EVIDENCE_DIR/logs/control-overlay.txt"
fi

mkdir -p "$EVIDENCE_DIR/overlay/Ui" "$EVIDENCE_DIR/overlay/Commons" "$EVIDENCE_DIR/harness"
cp -a "$WORKDIR/harness/qs/Ui/." "$EVIDENCE_DIR/overlay/Ui/"
cp -a "$WORKDIR/harness/qs/Commons/." "$EVIDENCE_DIR/overlay/Commons/"
cp -a "$HARNESS_SRC/." "$EVIDENCE_DIR/harness/"
cp -a "$ARCHIVE" "$EVIDENCE_DIR/candidate.tar"
{
  echo "overlay_dir=$EVIDENCE_DIR/overlay"
  (cd "$EVIDENCE_DIR/overlay" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
} | tee "$EVIDENCE_DIR/logs/overlay-files.sha256"
{
  echo "harness_src=$HARNESS_SRC"
  (cd "$EVIDENCE_DIR/harness" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
} | tee "$EVIDENCE_DIR/logs/harness-files.sha256"
sha256sum "$EVIDENCE_DIR/candidate.tar" | tee "$EVIDENCE_DIR/logs/candidate.tar.sha256"

# Isolated copy used only for omarchy plugin validate (not live HOME).
mkdir -p "$WORKDIR/home/.config/omarchy/plugins"
cp -a "$WORKDIR/plugin/." "$WORKDIR/home/.config/omarchy/plugins/tbassss.breadcrumb"

{
  echo "workdir=$WORKDIR"
  echo "candidate=${CANDIDATE_SHA:-unknown}"
  echo "plugin_files:"
  (cd "$WORKDIR/plugin" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
} | tee "$EVIDENCE_DIR/logs/candidate-files.sha256"

# Fake argv launchers for Process tests. Never xdg-open / real apps.
FAKE_OPEN_OK="$WORKDIR/fake-open-ok"
FAKE_OPEN_FAIL="$WORKDIR/fake-open-fail"
FAKE_OPEN_HANG="$WORKDIR/fake-open-hang"
FAKE_OPEN_HANG_PID="$WORKDIR/fake-open-hang.pid"
printf '%s\n' '#!/usr/bin/python3' 'raise SystemExit(0)' > "$FAKE_OPEN_OK"
printf '%s\n' '#!/usr/bin/python3' 'raise SystemExit(2)' > "$FAKE_OPEN_FAIL"
printf '%s\n' '#!/usr/bin/python3' \
  'import os, time' \
  'pid_path = os.environ.get("BREADCRUMB_FAKE_OPEN_HANG_PID", "")' \
  'if pid_path:' \
  '    with open(pid_path, "w", encoding="utf-8") as fh:' \
  '        fh.write(str(os.getpid()))' \
  '        fh.flush()' \
  '        os.fsync(fh.fileno())' \
  'while True:' \
  '    time.sleep(30)' > "$FAKE_OPEN_HANG"
chmod 755 "$FAKE_OPEN_OK" "$FAKE_OPEN_FAIL" "$FAKE_OPEN_HANG"
sha256sum "$FAKE_OPEN_OK" "$FAKE_OPEN_FAIL" "$FAKE_OPEN_HANG" | tee "$EVIDENCE_DIR/logs/fake-launchers.sha256"

export OMARCHY_PATH=/usr/share/omarchy
echo "=== omarchy plugin validate ==="
VALIDATE_OUT="$EVIDENCE_DIR/logs/omarchy-plugin-validate.txt"
set +e
omarchy plugin validate "$WORKDIR/home/.config/omarchy/plugins/tbassss.breadcrumb" >"$VALIDATE_OUT" 2>&1
VALIDATE_RC=$?
set -e
echo "validate_rc=$VALIDATE_RC"
cat "$VALIDATE_OUT"
if [[ $VALIDATE_RC -ne 0 ]]; then
  echo "omarchy plugin validate failed" >&2
  echo "$WORKDIR" > "$EVIDENCE_DIR/logs/workdir.path"
  exit $VALIDATE_RC
fi

RESULTS="$WORKDIR/results/ui-results.json"
QS_STDOUT="$EVIDENCE_DIR/logs/qs.stdout.log"
QS_STDERR="$EVIDENCE_DIR/logs/qs.stderr.log"

# Isolation: unique HOME/XDG, offscreen Qt, no Wayland/Hyprland, unique runtime dir.
# Do not pass WAYLAND_DISPLAY, DISPLAY, or HYPRLAND_INSTANCE_SIGNATURE.
set +e
env -i \
  HOME="$WORKDIR/home" \
  USER="${USER:-tbasss}" \
  PATH="/usr/bin:/bin" \
  LANG=C.UTF-8 \
  LC_ALL=C.UTF-8 \
  QT_QPA_PLATFORM=offscreen \
  QT_FORCE_STDERR_LOGGING=1 \
  QML_IMPORT_PATH="$WORKDIR/harness" \
  QML2_IMPORT_PATH="$WORKDIR/harness" \
  XDG_RUNTIME_DIR="$WORKDIR/runtime" \
  XDG_CONFIG_HOME="$WORKDIR/config" \
  XDG_DATA_HOME="$WORKDIR/data" \
  XDG_CACHE_HOME="$WORKDIR/cache" \
  XDG_STATE_HOME="$WORKDIR/state" \
  BREADCRUMB_DATA_DIR="$WORKDIR/breadcrumb-data" \
  BREADCRUMB_PLUGIN_DIR="$WORKDIR/plugin" \
  BREADCRUMB_RESULTS="$RESULTS" \
  BREADCRUMB_EVIDENCE="$EVIDENCE_DIR" \
  BREADCRUMB_NO_OPEN=1 \
  BREADCRUMB_FAKE_OPEN_OK="$FAKE_OPEN_OK" \
  BREADCRUMB_FAKE_OPEN_FAIL="$FAKE_OPEN_FAIL" \
  BREADCRUMB_FAKE_OPEN_HANG="$FAKE_OPEN_HANG" \
  BREADCRUMB_FAKE_OPEN_HANG_PID="$FAKE_OPEN_HANG_PID" \
  OMARCHY_PATH=/usr/share/omarchy \
  PYTHONDONTWRITEBYTECODE=1 \
  timeout 240 /usr/bin/qs -p "$WORKDIR/harness/shell.qml" --no-color -v \
  >"$QS_STDOUT" 2>"$QS_STDERR"
QS_RC=$?
set -e
echo "qs_rc=$QS_RC"

echo "=== qs stdout (tail) ==="
tail -n 80 "$QS_STDOUT" || true
echo "=== qs stderr (tail) ==="
tail -n 80 "$QS_STDERR" || true

if [[ -f "$RESULTS" ]]; then
  cp -a "$RESULTS" "$EVIDENCE_DIR/logs/ui-results.json"
  echo "=== ui-results.json ==="
  cat "$RESULTS"
else
  echo "NO_UI_RESULTS_FILE" | tee "$EVIDENCE_DIR/logs/ui-results.missing"
  python3 - <<PY
import pathlib, sys
src = pathlib.Path("$QS_STDOUT")
text = src.read_text(encoding="utf-8", errors="replace") if src.exists() else ""
key = "HARNESS_RESULT "
idx = text.rfind(key)
if idx < 0:
    sys.exit(0)
raw = text[idx + len(key):]
# JSON may be followed by more log lines; keep from first { to last matching dump
brace = raw.find("{")
if brace < 0:
    sys.exit(0)
raw = raw[brace:]
# trim trailing log after the JSON object by counting braces
depth = 0
end = None
in_str = False
esc = False
for i, ch in enumerate(raw):
    if in_str:
        if esc:
            esc = False
        elif ch == "\\\\":
            esc = True
        elif ch == '"':
            in_str = False
        continue
    if ch == '"':
        in_str = True
        continue
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = i + 1
            break
if end:
    out = pathlib.Path("$EVIDENCE_DIR/logs/ui-results.json")
    out.write_text(raw[:end], encoding="utf-8")
    print("recovered_ui_results_from_stdout bytes", end)
PY
  if [[ -f "$EVIDENCE_DIR/logs/ui-results.json" ]]; then
    RESULTS="$EVIDENCE_DIR/logs/ui-results.json"
  fi
fi

if [[ -d "$WORKDIR/breadcrumb-data" ]]; then
  (cd "$WORKDIR/breadcrumb-data" && find . -type f -print0 | sort -z | xargs -0 sha256sum) \
    | tee "$EVIDENCE_DIR/logs/breadcrumb-data.sha256" || true
  if [[ -f "$WORKDIR/breadcrumb-data/breadcrumb.sqlite" ]]; then
    cp -a "$WORKDIR/breadcrumb-data/breadcrumb.sqlite" "$EVIDENCE_DIR/logs/breadcrumb.sqlite"
    python3 - <<PY | tee "$EVIDENCE_DIR/logs/sqlite-readback.json"
import json, sqlite3, os
path = os.environ.get("SQLITE", "$WORKDIR/breadcrumb-data/breadcrumb.sqlite")
con = sqlite3.connect(path)
con.row_factory = sqlite3.Row
acts = [dict(r) for r in con.execute("SELECT id, name, created_at, archived_at FROM activities")]
cps = [dict(r) for r in con.execute("SELECT id, activity_id, revision, summary, next_step, context, state, author, saved_at FROM checkpoints ORDER BY revision")]
prefs = [dict(r) for r in con.execute("SELECT key, value FROM prefs")]
try:
    drafts = [dict(r) for r in con.execute("SELECT activity_id, revision, base_revision, summary, next_step, context, state, author, updated_at FROM drafts")]
except sqlite3.Error:
    drafts = []
print(json.dumps({"activities": acts, "checkpoints": cps, "prefs": prefs, "drafts": drafts}, indent=2))
PY
  fi
fi

LIVE_QS_PID_AFTER=$(pgrep -n -f 'quickshell -n -p /usr/share/omarchy/shell' || true)
echo "live_qs_pid_after=${LIVE_QS_PID_AFTER:-none}"
sha256sum "$LIVE_SHELL_JSON" | tee "$EVIDENCE_DIR/logs/live-shell.json.sha256.after"
if [[ -e "$LIVE_PLUGIN_DIR/tbassss.breadcrumb" ]]; then
  echo "LIVE_PLUGIN_CREATED_UNEXPECTEDLY" >&2
  exit 1
fi
echo "live plugin dir still has no tbassss.breadcrumb"

pgrep -af "qs -p $WORKDIR/harness/shell.qml" || true

echo "$WORKDIR" > "$EVIDENCE_DIR/logs/workdir.path"
echo "=== end $(ts) qs_rc=$QS_RC validate_rc=$VALIDATE_RC ==="
# Native assertion lives in ui-results.json (ok true/false). qs may exit 0 after writing a failure payload.
if [[ ! -f "$RESULTS" ]]; then
  exit 1
fi
python3 - <<PY
import json, sys
p = "$RESULTS"
data = json.loads(open(p, encoding="utf-8").read())
ok = bool(data.get("ok"))
print("ui_ok=" + str(ok).lower())
if not ok:
    print("ui_error=" + str(data.get("error", "")))
    sys.exit(1)
trav = data.get("traversalEvidence") or []
tags = {row.get("tag") for row in trav if isinstance(row, dict)}
need = {"save", "links-open", "history-restore"}
missing = sorted(need - tags)
if missing:
    print("missing traversal tags: " + ",".join(missing))
    sys.exit(1)
for row in trav:
    if not isinstance(row, dict):
        continue
    if row.get("tag") in need and not row.get("contained"):
        print("viewport containment failed for " + str(row.get("tag")))
        sys.exit(1)
elapsed = float(data.get("hangElapsedMs") or 0)
print("hangElapsedMs=" + str(elapsed))
if elapsed < 7500:
    print("hang elapsed shorter than production 8s timeout")
    sys.exit(1)
if int(data.get("reapCheckExit", 1)) != 0:
    print("hang child reap check failed")
    sys.exit(1)
routing = data.get("catcherRouting") or {}
if not routing.get("editorChanged"):
    print("editor j did not modify text in catcherRouting")
    sys.exit(1)
if not routing.get("popupOpen"):
    print("dropdown popupOpen was not recorded")
    sys.exit(1)
print("native extra asserts ok")
PY
