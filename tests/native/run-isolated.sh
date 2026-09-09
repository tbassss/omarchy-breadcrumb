#!/usr/bin/env bash
# Isolated Cave native validation for Breadcrumb issues #3, #4, and #5.
# Does NOT install/enable the plugin, restart the live shell, or write live config.
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

# Isolated copy used only for omarchy plugin validate (not live HOME).
mkdir -p "$WORKDIR/home/.config/omarchy/plugins"
cp -a "$WORKDIR/plugin/." "$WORKDIR/home/.config/omarchy/plugins/tbassss.breadcrumb"

{
  echo "workdir=$WORKDIR"
  echo "candidate=${CANDIDATE_SHA:-unknown}"
  echo "plugin_files:"
  (cd "$WORKDIR/plugin" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
} | tee "$EVIDENCE_DIR/logs/candidate-files.sha256"

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
  OMARCHY_PATH=/usr/share/omarchy \
  PYTHONDONTWRITEBYTECODE=1 \
  timeout 120 /usr/bin/qs -p "$WORKDIR/harness/shell.qml" --no-color -v \
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
PY
