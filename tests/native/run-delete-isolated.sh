#!/usr/bin/env bash
# Isolated Cave native deletion-journey validation.
# Does NOT install/enable the plugin, restart the live shell, or write live config.
# LIVE_PLUGIN_DIR points at an empty disposable directory so the runner absence
# guard is not the real plugin path. Real live plugin/shell hashes are snapshotted
# independently before and after. That absence assertion does not prove the live
# plugin is missing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANDIDATE_SHA="${CANDIDATE_SHA:-}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$PWD}"
HARNESS_SRC="${HARNESS_SRC:-$SCRIPT_DIR/harness}"
HARNESS_QML="${HARNESS_QML:-delete-shell.qml}"
ARCHIVE="${ARCHIVE:?ARCHIVE tar of exact candidate required}"

ts() { date -Is; }

REAL_LIVE_SHELL_JSON="${REAL_LIVE_SHELL_JSON:-/home/tbasss/.config/omarchy/shell.json}"
REAL_LIVE_PLUGIN="${REAL_LIVE_PLUGIN:-/home/tbasss/.config/omarchy/plugins/tbassss.breadcrumb}"
LIVE_PLUGIN_DIR="${LIVE_PLUGIN_DIR:-}"

mkdir -p "$EVIDENCE_DIR/logs" "$EVIDENCE_DIR/screenshots"

echo "=== begin $(ts) ==="
echo "candidate=${CANDIDATE_SHA:-unknown}"
echo "evidence=$EVIDENCE_DIR"
echo "archive=$ARCHIVE"
echo "harness=$HARNESS_SRC"
echo "harness_qml=$HARNESS_QML"

if [[ -z "$LIVE_PLUGIN_DIR" ]]; then
  LIVE_PLUGIN_DIR=$(mktemp -d /tmp/breadcrumb-live-plugin-absent-XXXX)
fi
mkdir -p "$LIVE_PLUGIN_DIR"
echo "LIVE_PLUGIN_DIR_OVERRIDE=$LIVE_PLUGIN_DIR"
echo "note=absence guard concerns this empty disposable directory, not the real installation"

LIVE_QS_PID=$(pgrep -n -f 'quickshell -n -p /usr/share/omarchy/shell' || true)
echo "live_qs_pid_before=${LIVE_QS_PID:-none}" | tee "$EVIDENCE_DIR/logs/live-qs-pid.before"
if [[ -n "${LIVE_QS_PID:-}" ]]; then
  tr '\0' '\n' < "/proc/${LIVE_QS_PID}/cmdline" | sed 's/^/  cmdline_part: /' | tee -a "$EVIDENCE_DIR/logs/live-qs-pid.before"
fi

if [[ ! -f "$REAL_LIVE_SHELL_JSON" ]]; then
  echo "missing live shell.json" >&2
  exit 1
fi
sha256sum "$REAL_LIVE_SHELL_JSON" | tee "$EVIDENCE_DIR/logs/real-live-shell.json.sha256.before"
if [[ -e "$REAL_LIVE_PLUGIN" ]]; then
  {
    echo "real_live_plugin=$REAL_LIVE_PLUGIN"
    (cd "$REAL_LIVE_PLUGIN" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
  } | tee "$EVIDENCE_DIR/logs/real-live-plugin.sha256.before"
else
  echo "real_live_plugin_absent" | tee "$EVIDENCE_DIR/logs/real-live-plugin.sha256.before"
fi

if [[ -e "$LIVE_PLUGIN_DIR/tbassss.breadcrumb" ]]; then
  echo "REFUSING: disposable LIVE_PLUGIN_DIR already has tbassss.breadcrumb" >&2
  ls -la "$LIVE_PLUGIN_DIR/tbassss.breadcrumb" >&2
  exit 1
fi

WORKDIR=$(mktemp -d /tmp/breadcrumb-native-delete-XXXX)
echo "WORKDIR=$WORKDIR" | tee "$EVIDENCE_DIR/logs/workdir.path"
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
  cp -a "$HARNESS_SRC/qs/Ui/KeyboardPanel.qml" "$WORKDIR/harness/qs/Ui/KeyboardPanel.qml"
  cp -a "$HARNESS_SRC/qs/Ui/Panel.qml" "$WORKDIR/harness/qs/Ui/Panel.qml"
  {
    echo "packaged_overlay=yes"
    echo "omarchy_shell=$OMARCHY_SHELL"
    echo "stubbed=KeyboardPanel,Panel"
    echo "bariconbutton_iconComponent=$(grep -c 'property Component iconComponent' "$WORKDIR/harness/qs/Ui/BarIconButton.qml" || true)"
    echo "button_declares_enabled=$(grep -c 'property bool enabled' "$WORKDIR/harness/qs/Ui/Button.qml" || true)"
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
sha256sum "$EVIDENCE_DIR/candidate.tar" | tee "$EVIDENCE_DIR/logs/candidate.tar.sha256"
{
  echo "plugin_runtime"
  sha256sum "$WORKDIR/plugin/Panel.qml" "$WORKDIR/plugin/bin/breadcrumb-store" "$WORKDIR/plugin/bin/breadcrumb" "$WORKDIR/plugin/Model.js"
} | tee "$EVIDENCE_DIR/logs/runtime-in-workdir.sha256"

mkdir -p "$WORKDIR/home/.config/omarchy/plugins"
cp -a "$WORKDIR/plugin/." "$WORKDIR/home/.config/omarchy/plugins/tbassss.breadcrumb"

FAKE_OPEN_OK="$WORKDIR/fake-open-ok"
FAKE_OPEN_FAIL="$WORKDIR/fake-open-fail"
printf '%s\n' '#!/usr/bin/python3' 'raise SystemExit(0)' > "$FAKE_OPEN_OK"
printf '%s\n' '#!/usr/bin/python3' 'raise SystemExit(2)' > "$FAKE_OPEN_FAIL"
chmod 755 "$FAKE_OPEN_OK" "$FAKE_OPEN_FAIL"

export OMARCHY_PATH=/usr/share/omarchy
echo "=== omarchy plugin validate (isolated HOME copy) ==="
VALIDATE_OUT="$EVIDENCE_DIR/logs/omarchy-plugin-validate.txt"
set +e
omarchy plugin validate "$WORKDIR/home/.config/omarchy/plugins/tbassss.breadcrumb" >"$VALIDATE_OUT" 2>&1
VALIDATE_RC=$?
set -e
echo "validate_rc=$VALIDATE_RC"
cat "$VALIDATE_OUT"
if [[ $VALIDATE_RC -ne 0 ]]; then
  echo "omarchy plugin validate failed" >&2
  exit $VALIDATE_RC
fi

RESULTS="$WORKDIR/results/ui-results.json"
QS_STDOUT="$EVIDENCE_DIR/logs/qs.stdout.log"
QS_STDERR="$EVIDENCE_DIR/logs/qs.stderr.log"

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
  OMARCHY_PATH=/usr/share/omarchy \
  PYTHONDONTWRITEBYTECODE=1 \
  timeout 200 /usr/bin/qs -p "$WORKDIR/harness/$HARNESS_QML" --no-color -v \
  >"$QS_STDOUT" 2>"$QS_STDERR"
QS_RC=$?
set -e
echo "qs_rc=$QS_RC" | tee "$EVIDENCE_DIR/logs/qs.rc"

echo "=== qs stdout (tail) ==="
tail -n 40 "$QS_STDOUT" || true
echo "=== qs stderr (tail) ==="
tail -n 80 "$QS_STDERR" || true

if [[ -f "$RESULTS" ]]; then
  cp -a "$RESULTS" "$EVIDENCE_DIR/logs/ui-results.json"
  cp -a "$RESULTS" "$EVIDENCE_DIR/ui-results.json"
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
brace = raw.find("{")
if brace < 0:
    sys.exit(0)
raw = raw[brace:]
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
    pathlib.Path("$EVIDENCE_DIR/ui-results.json").write_text(raw[:end], encoding="utf-8")
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
    python3 - "$WORKDIR/breadcrumb-data/breadcrumb.sqlite" <<'PY' | tee "$EVIDENCE_DIR/logs/sqlite-readback.json"
import json, sqlite3, sys
path = sys.argv[1]
con = sqlite3.connect(path)
con.row_factory = sqlite3.Row
acts = [dict(r) for r in con.execute("SELECT id, name, created_at, archived_at FROM activities")]
cps = [dict(r) for r in con.execute("SELECT id, activity_id, revision, summary FROM checkpoints ORDER BY revision")]
prefs = [dict(r) for r in con.execute("SELECT key, value FROM prefs")]
try:
    drafts = [dict(r) for r in con.execute("SELECT activity_id, revision, live, summary FROM drafts")]
except sqlite3.Error:
    drafts = []
print(json.dumps({"activities": acts, "checkpoints": cps, "prefs": prefs, "drafts": drafts}, indent=2))
PY
  fi
fi

LIVE_QS_PID_AFTER=$(pgrep -n -f 'quickshell -n -p /usr/share/omarchy/shell' || true)
echo "live_qs_pid_after=${LIVE_QS_PID_AFTER:-none}" | tee "$EVIDENCE_DIR/logs/live-qs-pid.after"
sha256sum "$REAL_LIVE_SHELL_JSON" | tee "$EVIDENCE_DIR/logs/real-live-shell.json.sha256.after"
if [[ -e "$REAL_LIVE_PLUGIN" ]]; then
  {
    echo "real_live_plugin=$REAL_LIVE_PLUGIN"
    (cd "$REAL_LIVE_PLUGIN" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
  } | tee "$EVIDENCE_DIR/logs/real-live-plugin.sha256.after"
else
  echo "real_live_plugin_absent" | tee "$EVIDENCE_DIR/logs/real-live-plugin.sha256.after"
fi
if [[ -e "$LIVE_PLUGIN_DIR/tbassss.breadcrumb" ]]; then
  echo "DISPOSABLE_LIVE_PLUGIN_DIR_CREATED_UNEXPECTEDLY" >&2
  exit 1
fi

python3 - <<PY
import pathlib, sys
before = pathlib.Path("$EVIDENCE_DIR/logs/real-live-plugin.sha256.before").read_text()
after = pathlib.Path("$EVIDENCE_DIR/logs/real-live-plugin.sha256.after").read_text()
shell_b = pathlib.Path("$EVIDENCE_DIR/logs/real-live-shell.json.sha256.before").read_text().split()[0]
shell_a = pathlib.Path("$EVIDENCE_DIR/logs/real-live-shell.json.sha256.after").read_text().split()[0]
pid_b = pathlib.Path("$EVIDENCE_DIR/logs/live-qs-pid.before").read_text().splitlines()[0]
pid_a = pathlib.Path("$EVIDENCE_DIR/logs/live-qs-pid.after").read_text().splitlines()[0]
ok = True
if before != after:
    print("LIVE PLUGIN HASH CHANGED")
    ok = False
if shell_b != shell_a:
    print("LIVE SHELL.JSON HASH CHANGED")
    ok = False
def pid(line):
    return line.split("=", 1)[-1].strip()
if pid(pid_b) != pid(pid_a):
    print("LIVE QS PID CHANGED", pid(pid_b), pid(pid_a))
    ok = False
if not ok:
    sys.exit(1)
print("live_plugin_shell_pid_unchanged=yes")
PY

echo "$WORKDIR" > "$EVIDENCE_DIR/logs/workdir.path"
echo "=== end $(ts) qs_rc=$QS_RC validate_rc=$VALIDATE_RC ==="
if [[ ! -f "$RESULTS" && -f "$EVIDENCE_DIR/logs/ui-results.json" ]]; then
  RESULTS="$EVIDENCE_DIR/logs/ui-results.json"
fi
if [[ ! -f "$RESULTS" ]]; then
  echo "missing ui-results" >&2
  exit 1
fi
python3 - <<PY
import json, sys
p = "$RESULTS"
data = json.loads(open(p, encoding="utf-8").read())
ok = bool(data.get("ok"))
print("ui_ok=" + str(ok).lower())
print("step=" + str(data.get("step")))
print("confirmText=" + str(data.get("confirmText", ""))[:200])
print("compactHadDelete=" + str(data.get("compactHadDelete")))
print("compactConfirmAfterCollapse=" + str(data.get("compactConfirmAfterCollapse")))
print("collapseCancelledConfirm=" + str(data.get("collapseCancelledConfirm")))
print("compactConfirmDeleted=" + str(data.get("compactConfirmDeleted")))
print("confirmResurrectedOnReexpand=" + str(data.get("confirmResurrectedOnReexpand")))
print("cancelLeftActivity=" + str(data.get("cancelLeftActivity")))
print("confirmNamedTarget=" + str(data.get("confirmNamedTarget")))
print("keyboardDefaultCancel=" + str(data.get("keyboardDefaultCancel")))
print("returnOnConfirmCancelled=" + str(data.get("returnOnConfirmCancelled")))
print("findings=" + json.dumps(data.get("findings")))
if not ok:
    print("ui_error=" + str(data.get("error", "")))
    sys.exit(1)
if not data.get("confirmNamedTarget"):
    print("confirmation did not name exact target")
    sys.exit(1)
if data.get("compactHadDelete"):
    print("compact showed Delete permanently request")
    sys.exit(1)
if data.get("compactConfirmAfterCollapse"):
    print("compact displayed delete confirmation after collapse")
    sys.exit(1)
if not data.get("collapseCancelledConfirm"):
    print("collapse did not cancel pending confirmation")
    sys.exit(1)
if data.get("compactConfirmDeleted"):
    print("compact executed permanent delete")
    sys.exit(1)
if data.get("confirmResurrectedOnReexpand"):
    print("confirmation resurrected on re-expand")
    sys.exit(1)
if not data.get("cancelLeftActivity"):
    print("cancel was not proven no-op")
    sys.exit(1)
if not data.get("keyboardDefaultCancel"):
    print("keyboard default was not Cancel")
    sys.exit(1)
if not data.get("returnOnConfirmCancelled"):
    print("Return on confirmation was not Cancel")
    sys.exit(1)
print("native deletion asserts ok")
PY
