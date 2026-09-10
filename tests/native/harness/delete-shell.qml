import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtTest

// In-repo isolated deletion-journey component driver.
// Real candidate Panel.qml + qs/Qt offscreen + packaged qs.Ui/qs.Commons overlay.
// KeyboardPanel and host Panel remain stubs. Not live bar / WlrLayershell.
// Asserts Compact cannot display or execute permanent-delete confirmation,
// collapse cancels pending confirmation, and re-expand does not resurrect it.
ShellRoot {
  id: harness

  property string pluginDir: Quickshell.env("BREADCRUMB_PLUGIN_DIR")
  property string resultsPath: Quickshell.env("BREADCRUMB_RESULTS")
  property int step: 0
  property int ticks: 0
  property int stepTicks: 0
  property bool finished: false
  property var snapshots: []
  property var qmlErrors: []
  property var screenshots: []
  property var findings: []
  property bool grabPending: false
  property string keepName: "Keep Lantern Notes"
  property string goneName: "Gone Trail Map"
  property string keepId: ""
  property string goneId: ""
  property string confirmText: ""
  property bool compactHadDelete: false
  property bool compactConfirmAfterCollapse: false
  property bool collapseCancelledConfirm: false
  property bool compactConfirmDeleted: false
  property bool confirmResurrectedOnReexpand: false
  property bool cancelLeftActivity: false
  property bool confirmNamedTarget: false
  property bool keyboardDefaultCancel: false
  property bool returnOnConfirmCancelled: false
  property string lastErrorSeen: ""
  property bool externalDone: false
  property int goneRevisionBeforeStale: 0
  property int frozenArchiveGeneration: -1
  property string frozenArchivedAt: ""
  property bool staleCycleRejected: false

  function panelObj() {
    return panelLoader.item
  }

  function isShown(item) {
    var n = item
    while (n) {
      if (n.visible === false)
        return false
      n = n.parent
    }
    return !!item
  }

  function findShownButton(item, text) {
    if (!item)
      return null
    if (item.text !== undefined && String(item.text) === text && isShown(item))
      return item
    var kids = item.children
    if (!kids)
      return null
    for (var i = 0; i < kids.length; i++) {
      var found = findShownButton(kids[i], text)
      if (found)
        return found
    }
    return null
  }

  function findShownTextPrefix(item, prefix) {
    if (!item)
      return null
    if (item.text !== undefined && String(item.text).indexOf(prefix) === 0 && isShown(item))
      return item
    var kids = item.children
    if (!kids)
      return null
    for (var i = 0; i < kids.length; i++) {
      var found = findShownTextPrefix(kids[i], prefix)
      if (found)
        return found
    }
    return null
  }

  function findNamed(item, name) {
    if (!item)
      return null
    if (item.objectName === name)
      return item
    var kids = item.children
    if (!kids)
      return null
    for (var i = 0; i < kids.length; i++) {
      var found = findNamed(kids[i], name)
      if (found)
        return found
    }
    return null
  }

  function clickShown(text, label) {
    var p = panelObj()
    var btn = findShownButton(p, text)
    if (!btn) {
      fail(label + " missing shown button text=" + text)
      return false
    }
    if (typeof btn.clicked !== "function") {
      fail(label + " button has no clicked() text=" + text)
      return false
    }
    btn.clicked()
    return true
  }

  function clickNamedOrText(name, text, label) {
    var p = panelObj()
    var btn = findNamed(p, name)
    if (btn && isShown(btn) && typeof btn.clicked === "function") {
      btn.clicked()
      return true
    }
    return clickShown(text, label)
  }

  function geomOf(name) {
    var item = findNamed(panelObj(), name)
    if (!item)
      return { name: name, missing: true }
    return {
      name: name,
      visible: !!item.visible,
      width: item.width,
      height: item.height,
      text: item.text !== undefined ? String(item.text) : ""
    }
  }

  function snap(tag) {
    var p = panelObj()
    if (!p)
      return { tag: tag, missing: true }
    var a = p.activity || null
    var confirm = p.deleteConfirm
    var targets = []
    if (typeof p.keyboardTargets === "function") {
      var kt = p.keyboardTargets()
      for (var i = 0; i < kt.length; i++) {
        var item = kt[i]
        targets.push(item && item.text !== undefined ? String(item.text) : (item && item.objectName ? String(item.objectName) : ""))
      }
    }
    return {
      tag: tag,
      loadState: p.loadState,
      lastError: p.lastError,
      view: p.view,
      expanded: !!p.expanded,
      opened: !!p.opened,
      busy: !!p.busy,
      dirty: !!p.dirty,
      hasDraft: !!p.hasDraft,
      draftRevision: p.draftRevision || 0,
      revision: p.revision || 0,
      hasActivity: !!p.hasActivity,
      activityId: a ? a.id : "",
      activityName: a ? a.name : "",
      archivedAt: a && a.archived_at ? a.archived_at : "",
      activityCount: (p.activities || []).length,
      activityNames: (p.activities || []).map(function(row) { return row.name }),
      deleteConfirm: confirm ? {
        activity_id: confirm.activity_id,
        expected_name: confirm.expected_name,
        expected_revision: confirm.expected_revision,
        expected_draft_revision: confirm.expected_draft_revision,
        expected_archived_at: confirm.expected_archived_at,
        expected_archive_generation: confirm.expected_archive_generation
      } : null,
      confirmText: confirmText,
      editSummary: p.editSummary,
      cursorIndex: p.cursorIndex,
      keyboardTargets: targets,
      compactColumn: geomOf("compactColumn")
    }
  }

  function payload(ok, extra) {
    var body = {
      ok: ok,
      step: step,
      ticks: ticks,
      snapshots: snapshots,
      qmlErrors: qmlErrors,
      screenshots: screenshots,
      findings: findings,
      keepId: keepId,
      goneId: goneId,
      confirmText: confirmText,
      compactHadDelete: compactHadDelete,
      compactConfirmAfterCollapse: compactConfirmAfterCollapse,
      collapseCancelledConfirm: collapseCancelledConfirm,
      compactConfirmDeleted: compactConfirmDeleted,
      confirmResurrectedOnReexpand: confirmResurrectedOnReexpand,
      cancelLeftActivity: cancelLeftActivity,
      confirmNamedTarget: confirmNamedTarget,
      keyboardDefaultCancel: keyboardDefaultCancel,
      returnOnConfirmCancelled: returnOnConfirmCancelled,
      lastErrorSeen: lastErrorSeen,
      staleCycleRejected: staleCycleRejected,
      frozenArchiveGeneration: frozenArchiveGeneration,
      classification: "component-test-not-full-host-integration",
      notes: "In-repo deletion harness. Real Panel.qml, packaged overlay, stub KeyboardPanel/Panel. Fictional data. Isolated HOME/XDG offscreen. Not live bar."
    }
    if (extra) {
      for (var k in extra)
        body[k] = extra[k]
    }
    return body
  }

  function fail(msg) {
    if (finished)
      return
    finished = true
    tickTimer.running = false
    console.log("HARNESS_FAIL " + msg)
    writeOut(payload(false, { error: msg, timeoutSnap: snap("fail") }))
  }

  function succeed() {
    if (finished)
      return
    finished = true
    tickTimer.running = false
    console.log("HARNESS_OK")
    writeOut(payload(true, {}))
  }

  function writeOut(obj) {
    var json = JSON.stringify(obj)
    console.log("HARNESS_RESULT " + json)
    Qt.quit()
  }

  Process {
    id: externalPub
    stdout: StdioCollector { id: extOut; waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      console.log("HARNESS_EXTERNAL_PUB exit=" + code + " out=" + extOut.text)
      if (code !== 0)
        fail("external publish failed: " + extOut.text)
      else
        externalDone = true
    }
  }

  function publishExternal(activityIdValue, expected, summary) {
    externalDone = false
    var payloadObj = {
      activity_id: activityIdValue,
      expected_revision: expected,
      summary: summary,
      next_step: "Review the conflict",
      state: "in_progress",
      author: "Agent"
    }
    externalPub.command = ["/usr/bin/python3", panelObj().storePath, "publish", JSON.stringify(payloadObj)]
    externalPub.running = true
  }

  Process {
    id: externalCycle
    stdout: StdioCollector { id: cycleOut; waitForEnd: true }
    stderr: StdioCollector { id: cycleErr; waitForEnd: true }
    onExited: function(code) {
      console.log("HARNESS_EXTERNAL_CYCLE exit=" + code + " out=" + cycleOut.text + " err=" + cycleErr.text)
      if (code !== 0)
        fail("external archive cycle failed: " + cycleOut.text + " " + cycleErr.text)
      else
        externalDone = true
    }
  }

  function cycleArchiveSameTime(activityIdValue, archivedAt) {
    externalDone = false
    var py = "import json,os,sqlite3,subprocess,sys\n"
      + "store,activity_id,archived_at=sys.argv[1],sys.argv[2],sys.argv[3]\n"
      + "data=os.environ['BREADCRUMB_DATA_DIR']\n"
      + "def run(cmd,payload):\n"
      + " subprocess.check_call([sys.executable,store,cmd,json.dumps(payload)])\n"
      + "run('unarchive-activity',{'activity_id':activity_id})\n"
      + "run('archive-activity',{'activity_id':activity_id})\n"
      + "conn=sqlite3.connect(os.path.join(data,'breadcrumb.sqlite'))\n"
      + "conn.execute('UPDATE activities SET archived_at=? WHERE id=?',(archived_at,activity_id))\n"
      + "conn.commit()\n"
    externalCycle.command = ["/usr/bin/python3", "-c", py, panelObj().storePath, activityIdValue, archivedAt]
    externalCycle.running = true
  }

  ApplicationWindow {
    id: hostWindow
    width: 960
    height: 1400
    visible: true
    color: "#101315"
    title: "breadcrumb-delete-harness"
    Loader {
      id: panelLoader
      anchors.fill: parent
      active: true
      source: pluginDir !== "" ? ("file://" + pluginDir + "/Panel.qml") : ""
    }
    TestCase {
      id: keyDriver
      name: "keyInjector"
      when: false
    }
  }

  Timer {
    interval: 180000
    running: true
    repeat: false
    onTriggered: fail("watchdog timeout at step " + step)
  }

  Timer {
    id: tickTimer
    interval: 50
    running: true
    repeat: true
    onTriggered: harness.tick()
  }

  function idle() {
    var p = panelObj()
    return !!(p && !p.busy && p.loadState !== "loading" && p.draftStatus !== "saving")
  }

  function grabShot(tag) {
    var target = findNamed(panelObj(), "breadcrumbPanel")
    if (!target)
      target = hostWindow.contentItem
    if (!target || typeof target.grabToImage !== "function") {
      screenshots.push({ tag: tag, error: "grabToImage missing" })
      return
    }
    grabPending = true
    target.grabToImage(function(result) {
      var dir = Quickshell.env("BREADCRUMB_EVIDENCE")
      var path = dir + "/screenshots/" + tag + ".png"
      var saved = false
      try {
        saved = result.saveToFile(path)
      } catch (e) {
        saved = false
      }
      screenshots.push({ tag: tag, path: path, saved: saved, width: target.width, height: target.height })
      grabPending = false
    })
  }

  function namesOf(p) {
    return (p.activities || []).map(function(row) { return row.name })
  }

  function tick() {
    if (finished)
      return
    if (grabPending)
      return
    ticks += 1
    stepTicks += 1
    if (stepTicks > 200) {
      fail("timeout in step " + step)
      return
    }
    var p = panelObj()

    if (step === 0) {
      if (panelLoader.status === Loader.Error) {
        fail("Panel.qml failed to load")
        return
      }
      if (panelLoader.status !== Loader.Ready || !p)
        return
      snapshots.push(snap("loaded"))
      step = 1
      stepTicks = 0
      return
    }

    if (step === 1) {
      if (!idle())
        return
      if (p.loadState === "error") {
        fail("initial load error: " + p.lastError)
        return
      }
      if (!p.opened)
        p.open()
      p.editName = keepName
      p.createActivity()
      step = 2
      stepTicks = 0
      return
    }

    if (step === 2) {
      if (!idle())
        return
      if (!p.hasActivity || p.activity.name !== keepName) {
        fail("keep create failed")
        return
      }
      keepId = p.activity.id
      if (!p.expanded)
        p.toggleView()
      step = 3
      stepTicks = 0
      return
    }

    if (step === 3) {
      if (!idle())
        return
      if (!p.expanded) {
        fail("did not expand")
        return
      }
      p.editSummary = "Keep published lantern count"
      p.editNext = "Keep next"
      p.editContext = "Keep context"
      p.editState = "in_progress"
      p.editAuthor = "Reviewer"
      p.saveCheckpoint()
      step = 4
      stepTicks = 0
      return
    }

    if (step === 4) {
      if (!idle())
        return
      if (p.lastError !== "" || !p.hasCurrent) {
        fail("keep save failed: " + p.lastError)
        return
      }
      p.createName = goneName
      p.createActivity()
      step = 5
      stepTicks = 0
      return
    }

    if (step === 5) {
      if (!idle())
        return
      if (!p.hasActivity || p.activity.name !== goneName) {
        fail("gone create failed name=" + (p.activity ? p.activity.name : "none"))
        return
      }
      goneId = p.activity.id
      p.editSummary = "Gone published trail notes"
      p.editNext = "Gone next"
      p.editContext = "Gone context"
      p.editState = "in_progress"
      p.editAuthor = "Reviewer"
      p.saveCheckpoint()
      step = 6
      stepTicks = 0
      return
    }

    if (step === 6) {
      if (!idle())
        return
      p.editSummary = "Gone durable draft must vanish on delete"
      p.editNext = "Draft next"
      p.dirty = true
      p.saveDraft()
      step = 7
      stepTicks = 0
      return
    }

    if (step === 7) {
      if (!idle())
        return
      if (!p.hasDraft) {
        fail("gone draft did not persist")
        return
      }
      p.archiveActivity(goneId)
      step = 8
      stepTicks = 0
      return
    }

    if (step === 8) {
      if (!idle())
        return
      if (!p.activity || !p.activity.archived_at) {
        fail("archive did not stick")
        return
      }
      p.showArchived = true
      p.refresh()
      step = 9
      stepTicks = 0
      return
    }

    if (step === 9) {
      if (!idle())
        return
      if (p.expanded)
        p.toggleView()
      step = 10
      stepTicks = 0
      return
    }

    if (step === 10) {
      if (!idle())
        return
      if (p.expanded) {
        fail("did not collapse for compact probe")
        return
      }
      compactHadDelete = !!findShownButton(p, "Delete permanently")
      snapshots.push(snap("compact-no-delete"))
      if (compactHadDelete) {
        fail("compact showed Delete permanently request")
        return
      }
      if (!p.expanded)
        p.toggleView()
      step = 11
      stepTicks = 0
      return
    }

    if (step === 11) {
      if (!idle())
        return
      if (!p.expanded) {
        fail("did not expand for delete request")
        return
      }
      if (p.activity.name !== goneName) {
        fail("not on gone before request")
        return
      }
      if (!clickNamedOrText("deleteRequestButton", "Delete permanently", "request"))
        return
      step = 12
      stepTicks = 0
      return
    }

    if (step === 12) {
      if (!idle())
        return
      if (!p.deleteConfirm) {
        fail("confirmation did not open")
        return
      }
      var node = findShownTextPrefix(p, "Permanently delete")
      confirmText = node ? String(node.text) : ""
      confirmNamedTarget = confirmText.indexOf('"' + goneName + '"') >= 0
        && confirmText.indexOf("checkpoints") >= 0
        && confirmText.indexOf("history") >= 0
        && confirmText.indexOf("links") >= 0
        && confirmText.indexOf("draft") >= 0
      if (!confirmNamedTarget) {
        fail("confirmation text missing exact target or warning: " + confirmText)
        return
      }
      if (p.deleteConfirm.expected_name !== goneName || p.deleteConfirm.activity_id !== goneId) {
        fail("frozen confirmation identity mismatch")
        return
      }
      snapshots.push(snap("confirm-open"))
      grabShot("confirm-open")
      step = 13
      stepTicks = 0
      return
    }

    if (step === 13) {
      if (grabPending)
        return
      if (p.expanded)
        p.toggleView()
      step = 14
      stepTicks = 0
      return
    }

    if (step === 14) {
      if (!idle())
        return
      if (p.expanded) {
        fail("did not collapse with pending confirmation")
        return
      }
      compactConfirmAfterCollapse = !!findShownTextPrefix(p, "Permanently delete") || !!findShownButton(p, "Delete permanently")
      collapseCancelledConfirm = !p.deleteConfirm
      snapshots.push(snap("compact-after-confirm-open"))
      grabShot("compact-after-confirm-open")
      if (compactConfirmAfterCollapse) {
        fail("compact displayed permanent delete confirmation after collapse")
        return
      }
      if (!collapseCancelledConfirm) {
        fail("collapse left pending deleteConfirm")
        return
      }
      p.confirmDeleteArchived()
      step = 15
      stepTicks = 0
      return
    }

    if (step === 15) {
      if (grabPending)
        return
      if (!idle())
        return
      compactConfirmDeleted = !(p.activity && p.activity.id === goneId) || namesOf(p).indexOf(goneName) < 0
      if (compactConfirmDeleted) {
        fail("compact confirmDeleteArchived deleted the activity")
        return
      }
      if (!p.expanded)
        p.toggleView()
      step = 16
      stepTicks = 0
      return
    }

    if (step === 16) {
      if (!idle())
        return
      if (!p.expanded) {
        fail("did not re-expand after collapse cancel")
        return
      }
      confirmResurrectedOnReexpand = !!p.deleteConfirm || !!findShownTextPrefix(p, "Permanently delete")
      snapshots.push(snap("reexpand-no-confirm"))
      if (confirmResurrectedOnReexpand) {
        fail("confirmation resurrected on re-expand")
        return
      }
      if (!(p.activity && p.activity.id === goneId && p.activity.archived_at)) {
        fail("gone activity missing after collapse cancel")
        return
      }
      if (!clickNamedOrText("deleteRequestButton", "Delete permanently", "request-keyboard"))
        return
      step = 17
      stepTicks = 0
      return
    }

    if (step === 17) {
      if (!idle())
        return
      if (!p.deleteConfirm) {
        fail("confirmation did not open for keyboard")
        return
      }
      var kt = (typeof p.keyboardTargets === "function") ? p.keyboardTargets() : []
      keyboardDefaultCancel = kt.length >= 1 && kt[0] && String(kt[0].text) === "Cancel"
      if (!keyboardDefaultCancel) {
        fail("keyboard default was not Cancel targets=" + (kt.length))
        return
      }
      if (p.cursorIndex !== 0) {
        fail("cursorIndex was not Cancel after request got=" + p.cursorIndex)
        return
      }
      p.cursorActive = true
      p.activateKeyboardCursor()
      step = 18
      stepTicks = 0
      return
    }

    if (step === 18) {
      if (!idle())
        return
      returnOnConfirmCancelled = !p.deleteConfirm && !!(p.activity && p.activity.id === goneId && p.activity.archived_at)
      if (!returnOnConfirmCancelled) {
        fail("Return on confirmation was not a Cancel no-op")
        return
      }
      cancelLeftActivity = returnOnConfirmCancelled
      snapshots.push(snap("after-keyboard-cancel"))
      if (!clickNamedOrText("deleteRequestButton", "Delete permanently", "request-before-switch"))
        return
      step = 19
      stepTicks = 0
      return
    }

    if (step === 19) {
      if (!idle())
        return
      if (!p.deleteConfirm) {
        fail("confirm missing before switch")
        return
      }
      p.switchActivity(keepId)
      step = 20
      stepTicks = 0
      return
    }

    if (step === 20) {
      if (!idle())
        return
      if (p.deleteConfirm) {
        fail("switch did not clear confirmation")
        return
      }
      if (p.activity.id !== keepId) {
        fail("switch did not land on keep")
        return
      }
      if (namesOf(p).indexOf(goneName) < 0) {
        fail("switch cleared confirmation but deleted the target")
        return
      }
      snapshots.push(snap("after-switch-clears-confirm"))
      p.showArchived = true
      p.switchActivity(goneId)
      step = 21
      stepTicks = 0
      return
    }

    if (step === 21) {
      if (!idle())
        return
      if (p.activity.id !== goneId) {
        fail("did not return to gone")
        return
      }
      goneRevisionBeforeStale = p.revision
      if (!clickNamedOrText("deleteRequestButton", "Delete permanently", "request-before-stale"))
        return
      step = 22
      stepTicks = 0
      return
    }

    if (step === 22) {
      if (!idle())
        return
      if (!p.deleteConfirm) {
        fail("confirm missing before stale publish")
        return
      }
      publishExternal(goneId, goneRevisionBeforeStale, "Agent published after confirm opened")
      step = 23
      stepTicks = 0
      return
    }

    if (step === 23) {
      if (!externalDone)
        return
      if (!clickNamedOrText("deleteConfirmButton", "Delete permanently", "confirm-stale"))
        return
      step = 24
      stepTicks = 0
      return
    }

    if (step === 24) {
      if (!idle())
        return
      lastErrorSeen = p.lastError || ""
      if (!lastErrorSeen) {
        fail("stale confirm did not surface lastError")
        return
      }
      if (!p.activity || p.activity.id !== goneId) {
        fail("stale confirm deleted the activity")
        return
      }
      snapshots.push(snap("after-stale-confirm"))
      findings.push("stale_confirm_left_root_revision=" + p.revision + "_store_published_after=" + (goneRevisionBeforeStale + 1))
      if (!clickShown("Reload", "reload-after-stale"))
        return
      step = 25
      stepTicks = 0
      return
    }

    if (step === 25) {
      if (!idle())
        return
      if (p.revision <= goneRevisionBeforeStale) {
        fail("reload did not adopt newer published revision got=" + p.revision)
        return
      }
      if (!clickNamedOrText("deleteRequestButton", "Delete permanently", "request-final"))
        return
      step = 250
      stepTicks = 0
      return
    }

    if (step === 250) {
      if (!idle())
        return
      if (!p.deleteConfirm) {
        fail("cycle confirmation did not open")
        return
      }
      if (p.deleteConfirm.expected_revision <= goneRevisionBeforeStale) {
        fail("cycle freeze reused stale revision")
        return
      }
      if (p.deleteConfirm.expected_archive_generation === undefined || p.deleteConfirm.expected_archive_generation === null) {
        fail("cycle freeze missing expected_archive_generation")
        return
      }
      frozenArchiveGeneration = Number(p.deleteConfirm.expected_archive_generation)
      frozenArchivedAt = String(p.deleteConfirm.expected_archived_at || "")
      if (!frozenArchivedAt) {
        fail("cycle freeze missing expected_archived_at")
        return
      }
      cycleArchiveSameTime(goneId, frozenArchivedAt)
      step = 251
      stepTicks = 0
      return
    }

    if (step === 251) {
      if (!externalDone)
        return
      if (!clickNamedOrText("deleteConfirmButton", "Delete permanently", "confirm-stale-cycle"))
        return
      step = 252
      stepTicks = 0
      return
    }

    if (step === 252) {
      if (!idle())
        return
      lastErrorSeen = p.lastError || ""
      if (!lastErrorSeen) {
        fail("same-time unarchive/rearchive confirm did not surface lastError")
        return
      }
      if (!p.activity || p.activity.id !== goneId) {
        fail("same-time cycle confirm deleted the activity")
        return
      }
      if (namesOf(p).indexOf(goneName) < 0) {
        fail("same-time cycle confirm removed gone from the list")
        return
      }
      staleCycleRejected = true
      findings.push("stale_cycle_left_generation_frozen=" + frozenArchiveGeneration)
      snapshots.push(snap("after-stale-cycle-confirm"))
      if (!clickShown("Reload", "reload-after-stale-cycle"))
        return
      step = 253
      stepTicks = 0
      return
    }

    if (step === 253) {
      if (!idle())
        return
      if (!p.activity || p.activity.id !== goneId || !p.activity.archived_at) {
        fail("reload after stale cycle lost archived gone")
        return
      }
      if (Number(p.activity.archive_generation || 0) <= frozenArchiveGeneration) {
        fail("reload after stale cycle did not advance archive_generation")
        return
      }
      if (!clickNamedOrText("deleteRequestButton", "Delete permanently", "request-final"))
        return
      step = 254
      stepTicks = 0
      return
    }

    if (step === 254) {
      if (!idle())
        return
      if (!p.deleteConfirm) {
        fail("final confirmation did not open")
        return
      }
      if (Number(p.deleteConfirm.expected_archive_generation) <= frozenArchiveGeneration) {
        fail("final freeze reused stale archive_generation")
        return
      }
      if (!clickNamedOrText("deleteConfirmButton", "Delete permanently", "confirm-final"))
        return
      step = 26
      stepTicks = 0
      return
    }

    if (step === 26) {
      if (!idle())
        return
      if (namesOf(p).indexOf(goneName) >= 0) {
        fail("gone remained after confirm delete names=" + namesOf(p).join(","))
        return
      }
      if (p.activity && p.activity.id === goneId) {
        fail("ui still selected deleted activity")
        return
      }
      if (!p.activity || p.activity.id !== keepId) {
        fail("selection did not fall back to keep")
        return
      }
      snapshots.push(snap("after-delete"))
      grabShot("after-delete")
      step = 27
      stepTicks = 0
      return
    }

    if (step === 27) {
      if (grabPending)
        return
      p.archiveActivity(keepId)
      step = 28
      stepTicks = 0
      return
    }

    if (step === 28) {
      if (!idle())
        return
      p.showArchived = true
      p.refresh()
      step = 29
      stepTicks = 0
      return
    }

    if (step === 29) {
      if (!idle())
        return
      if (!p.expanded)
        p.toggleView()
      step = 30
      stepTicks = 0
      return
    }

    if (step === 30) {
      if (!idle())
        return
      if (!p.activity || p.activity.id !== keepId || !p.activity.archived_at) {
        fail("keep was not archived for last-entity delete")
        return
      }
      if (!clickNamedOrText("deleteRequestButton", "Delete permanently", "request-last"))
        return
      step = 31
      stepTicks = 0
      return
    }

    if (step === 31) {
      if (!idle())
        return
      if (!p.deleteConfirm) {
        fail("last-entity confirmation missing")
        return
      }
      if (!clickNamedOrText("deleteConfirmButton", "Delete permanently", "confirm-last"))
        return
      step = 32
      stepTicks = 0
      return
    }

    if (step === 32) {
      if (!idle())
        return
      if (p.hasActivity) {
        fail("last entity delete did not reach empty state")
        return
      }
      if ((p.activities || []).length !== 0) {
        fail("activities remained after last delete")
        return
      }
      snapshots.push(snap("empty-after-last"))
      grabShot("empty-after-last")
      step = 33
      stepTicks = 0
      return
    }

    if (step === 33) {
      if (grabPending)
        return
      succeed()
    }
  }
}
