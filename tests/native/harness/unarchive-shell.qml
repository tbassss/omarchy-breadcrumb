import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtTest

// In-repo isolated unarchive-journey component driver.
// Real candidate Panel.qml + qs/Qt offscreen + packaged qs.Ui/qs.Commons overlay.
// KeyboardPanel and host Panel remain stubs. Not live bar / WlrLayershell.
// Unarchive is one-click, distinct from history Restore and permanent Delete.
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
  property int goneRevisionBefore: 0
  property string inMemoryDraft: "Gone in-memory draft must survive unarchive"
  property bool compactHadUnarchive: false
  property bool compactHadDelete: false
  property bool unarchivePreservedSelection: false
  property bool unarchivePreservedRevision: false
  property bool unarchivePreservedDraft: false
  property bool deleteHiddenAfterUnarchive: false
  property bool confirmClearedOnUnarchive: false
  property bool keyboardUnarchivePresent: false
  property bool keyboardUnarchiveActivated: false
  property bool neighborKept: false

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

  function keyboardLabels(p) {
    var targets = []
    if (typeof p.keyboardTargets === "function") {
      var kt = p.keyboardTargets()
      for (var i = 0; i < kt.length; i++) {
        var item = kt[i]
        targets.push(item && item.text !== undefined ? String(item.text) : (item && item.objectName ? String(item.objectName) : ""))
      }
    }
    return targets
  }

  function snap(tag) {
    var p = panelObj()
    if (!p)
      return { tag: tag, missing: true }
    var a = p.activity || null
    var confirm = p.deleteConfirm
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
        expected_name: confirm.expected_name
      } : null,
      editSummary: p.editSummary,
      keyboardTargets: keyboardLabels(p),
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
      compactHadUnarchive: compactHadUnarchive,
      compactHadDelete: compactHadDelete,
      unarchivePreservedSelection: unarchivePreservedSelection,
      unarchivePreservedRevision: unarchivePreservedRevision,
      unarchivePreservedDraft: unarchivePreservedDraft,
      deleteHiddenAfterUnarchive: deleteHiddenAfterUnarchive,
      confirmClearedOnUnarchive: confirmClearedOnUnarchive,
      keyboardUnarchivePresent: keyboardUnarchivePresent,
      keyboardUnarchiveActivated: keyboardUnarchiveActivated,
      neighborKept: neighborKept,
      classification: "component-test-not-full-host-integration",
      notes: "In-repo unarchive harness. Real Panel.qml, packaged overlay, stub KeyboardPanel/Panel. Fictional data. Isolated HOME/XDG offscreen. Not live bar."
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

  ApplicationWindow {
    id: hostWindow
    width: 960
    height: 1400
    visible: true
    color: "#101315"
    title: "breadcrumb-unarchive-harness"
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
      goneRevisionBefore = p.revision
      p.editSummary = "Gone durable draft"
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
      p.editSummary = inMemoryDraft
      p.dirty = true
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
      compactHadUnarchive = !!findShownButton(p, "Unarchive")
      compactHadDelete = !!findShownButton(p, "Delete permanently")
      snapshots.push(snap("compact-no-unarchive"))
      if (compactHadUnarchive) {
        fail("compact showed Unarchive")
        return
      }
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
        fail("did not expand for unarchive")
        return
      }
      if (!(p.activity && p.activity.id === goneId && p.activity.archived_at)) {
        fail("not on archived gone before unarchive")
        return
      }
      if (findShownButton(p, "Restore") && findShownButton(p, "Unarchive") === findShownButton(p, "Restore")) {
        fail("Unarchive collided with Restore")
        return
      }
      if (!findShownButton(p, "Unarchive")) {
        fail("Unarchive missing on expanded archived activity")
        return
      }
      if (!findShownButton(p, "Delete permanently")) {
        fail("Delete permanently missing on archived activity")
        return
      }
      var labels = keyboardLabels(p)
      keyboardUnarchivePresent = labels.indexOf("Unarchive") >= 0
      if (!keyboardUnarchivePresent) {
        fail("keyboard Unarchive missing")
        return
      }
      snapshots.push(snap("expanded-archived"))
      grabShot("expanded-archived")
      step = 12
      stepTicks = 0
      return
    }

    if (step === 12) {
      if (grabPending)
        return
      if (!clickNamedOrText("deleteRequestButton", "Delete permanently", "request-before-unarchive"))
        return
      step = 13
      stepTicks = 0
      return
    }

    if (step === 13) {
      if (!idle())
        return
      if (!p.deleteConfirm) {
        fail("confirmation did not open before unarchive")
        return
      }
      if (!clickNamedOrText("unarchiveButton", "Unarchive", "unarchive-click"))
        return
      step = 14
      stepTicks = 0
      return
    }

    if (step === 14) {
      if (!idle())
        return
      confirmClearedOnUnarchive = !p.deleteConfirm
      if (!confirmClearedOnUnarchive) {
        fail("pending delete confirm survived unarchive")
        return
      }
      unarchivePreservedSelection = !!(p.activity && p.activity.id === goneId && p.activity.name === goneName)
      if (!unarchivePreservedSelection) {
        fail("unarchive did not preserve selection")
        return
      }
      if (p.activity.archived_at) {
        fail("activity remained archived")
        return
      }
      unarchivePreservedRevision = p.revision === goneRevisionBefore
      if (!unarchivePreservedRevision) {
        fail("unarchive appended a checkpoint")
        return
      }
      unarchivePreservedDraft = p.editSummary === inMemoryDraft
      if (!unarchivePreservedDraft) {
        fail("unarchive dropped in-memory draft")
        return
      }
      var deleteBtn = findNamed(p, "deleteRequestButton")
      deleteHiddenAfterUnarchive = !findShownButton(p, "Delete permanently") && !(deleteBtn && deleteBtn.visible)
      if (!deleteHiddenAfterUnarchive) {
        fail("delete remained after unarchive")
        return
      }
      if (findShownButton(p, "Unarchive")) {
        fail("Unarchive remained on active activity")
        return
      }
      neighborKept = namesOf(p).indexOf(keepName) >= 0
      if (!neighborKept) {
        fail("neighbor activity missing after unarchive")
        return
      }
      snapshots.push(snap("after-unarchive"))
      grabShot("after-unarchive")
      step = 15
      stepTicks = 0
      return
    }

    if (step === 15) {
      if (grabPending)
        return
      p.archiveActivity(goneId)
      step = 16
      stepTicks = 0
      return
    }

    if (step === 16) {
      if (!idle())
        return
      if (!(p.activity && p.activity.id === goneId && p.activity.archived_at)) {
        fail("re-archive failed before keyboard unarchive")
        return
      }
      var kt = (typeof p.keyboardTargets === "function") ? p.keyboardTargets() : []
      var idx = -1
      for (var i = 0; i < kt.length; i++) {
        if (kt[i] && (kt[i].objectName === "unarchiveButton" || String(kt[i].text) === "Unarchive"))
          idx = i
      }
      if (idx < 0) {
        fail("keyboard Unarchive missing")
        return
      }
      p.cursorActive = true
      p.cursorIndex = idx
      p.applyCursorHighlight()
      p.activateKeyboardCursor()
      step = 17
      stepTicks = 0
      return
    }

    if (step === 17) {
      if (!idle())
        return
      keyboardUnarchiveActivated = !!(p.activity && p.activity.id === goneId && !p.activity.archived_at)
      if (!keyboardUnarchiveActivated) {
        fail("keyboard Unarchive did not activate")
        return
      }
      neighborKept = namesOf(p).indexOf(keepName) >= 0 && namesOf(p).indexOf(goneName) >= 0
      snapshots.push(snap("after-keyboard-unarchive"))
      grabShot("after-keyboard-unarchive")
      step = 18
      stepTicks = 0
      return
    }

    if (step === 18) {
      if (grabPending)
        return
      succeed()
    }
  }
}
