import Quickshell
import Quickshell.Io
import QtQuick

// Isolated offscreen component driver for Breadcrumb #3 Panel.qml.
// Classification: real candidate Panel.qml + real qs/Qt runtime + minimal
// fake qs.Ui/qs.Commons. Not full omarchy-shell host integration.
//
// Regression for editor hydration after Panel recreate, plus same-instance
// genuine-draft preservation on refresh. Construction-time TextField
// onTextChanged must not be treated as a user draft.
ShellRoot {
  id: harness

  property string pluginDir: Quickshell.env("BREADCRUMB_PLUGIN_DIR")
  property string resultsPath: Quickshell.env("BREADCRUMB_RESULTS")
  property int step: 0
  property int ticks: 0
  property int stepTicks: 0
  property bool finished: false
  property var snapshots: []
  property string expectedName: "Fictional Garden Path"
  property string expectedSummary: "Cataloged the brass lantern inventory"
  property string expectedNext: "Sketch the east tunnel map"
  property string expectedContext: "Issue #3 native harness only"
  property string expectedState: "in_progress"
  property string expectedAuthor: "You"
  property string draftSummary: "Unsaved lantern draft — do not clobber"
  property string draftNext: "Keep this next-step draft"
  property string activityId: ""
  property int savedRevision: 0
  property var qmlErrors: []

  function panelObj() {
    return panelLoader.item
  }

  function snap(tag) {
    var p = panelObj()
    if (!p)
      return { tag: tag, missing: true }
    var a = p.activity || null
    var c = p.current || null
    return {
      tag: tag,
      loadState: p.loadState,
      lastError: p.lastError,
      view: p.view,
      expanded: p.expanded,
      opened: p.opened,
      busy: p.busy,
      dirty: p.dirty,
      hasActivity: p.hasActivity,
      hasCurrent: p.hasCurrent,
      revision: p.revision,
      activityId: a ? a.id : "",
      activityName: a ? a.name : "",
      summary: c ? c.summary : "",
      nextStep: c ? c.next_step : "",
      context: c ? c.context : "",
      state: c ? c.state : "",
      author: c ? c.author : "",
      savedAt: c ? c.saved_at : "",
      editName: p.editName,
      editSummary: p.editSummary,
      editNext: p.editNext,
      editContext: p.editContext,
      editState: p.editState,
      editAuthor: p.editAuthor,
      storePath: p.storePath
    }
  }

  function payload(ok, extra) {
    var body = {
      ok: ok,
      step: step,
      ticks: ticks,
      snapshots: snapshots,
      activityId: activityId,
      savedRevision: savedRevision,
      qmlErrors: qmlErrors,
      classification: "component-test-not-full-host-integration",
      notes: "Real Panel.qml driven through createActivity/saveCheckpoint/toggleView/close/open, genuine in-memory draft refresh, and Loader recreate. Host qs.Ui/qs.Commons are a minimal facade of inspected Cave APIs. KeyboardPanel is stubbed to avoid WlrLayershell. Not a live bar install. Not a source-only substitute: recreate asserts editSummary===current.summary on the live qs instance."
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

  Process {
    id: writer
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(code) {
      console.log("HARNESS_WROTE exit=" + code + " text=" + writer.stdout.text)
      Qt.quit()
    }
  }

  function writeOut(obj) {
    var json = JSON.stringify(obj)
    console.log("HARNESS_RESULT " + json)
    writer.command = ["/usr/bin/python3", "-c", "import os,sys; p=os.environ['BREADCRUMB_RESULTS']; open(p,'w',encoding='utf-8').write(sys.argv[1]); print('WROTE', p, len(sys.argv[1]))", json]
    writer.running = true
  }

  Loader {
    id: panelLoader
    active: true
    source: pluginDir !== "" ? ("file://" + pluginDir + "/Panel.qml") : ""
  }

  Timer {
    interval: 20000
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
    return !!(p && !p.busy && p.loadState !== "loading")
  }

  function tick() {
    if (finished)
      return
    ticks += 1
    stepTicks += 1
    if (stepTicks > 100) {
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
      snapshots.push(snap("initial"))
      p.editName = expectedName
      p.createActivity()
      step = 2
      stepTicks = 0
      return
    }

    if (step === 2) {
      if (!idle())
        return
      if (!p.hasActivity) {
        fail("createActivity did not produce activity")
        return
      }
      if (p.activity.name !== expectedName) {
        fail("activity name mismatch: " + p.activity.name)
        return
      }
      activityId = p.activity.id
      snapshots.push(snap("created"))
      if (!p.expanded)
        p.toggleView()
      step = 3
      stepTicks = 0
      return
    }

    if (step === 3) {
      if (!idle())
        return
      if (!p.expanded || p.view !== "expanded") {
        fail("toggleView did not expand")
        return
      }
      snapshots.push(snap("expanded"))
      p.editSummary = expectedSummary
      p.editNext = expectedNext
      p.editContext = expectedContext
      p.editState = expectedState
      p.editAuthor = expectedAuthor
      p.saveCheckpoint()
      step = 4
      stepTicks = 0
      return
    }

    if (step === 4) {
      if (!idle())
        return
      if (p.lastError !== "") {
        fail("save error: " + p.lastError)
        return
      }
      if (!p.hasCurrent) {
        fail("save did not set current")
        return
      }
      if (p.current.summary !== expectedSummary) {
        fail("UI summary mismatch after save")
        return
      }
      if (p.current.next_step !== expectedNext) {
        fail("UI next mismatch after save")
        return
      }
      if (p.current.context !== expectedContext) {
        fail("UI context mismatch after save")
        return
      }
      if (p.current.state !== expectedState) {
        fail("UI state mismatch after save")
        return
      }
      if (p.current.author !== expectedAuthor) {
        fail("UI author mismatch after save")
        return
      }
      if (p.revision < 1) {
        fail("revision not incremented")
        return
      }
      savedRevision = p.revision
      snapshots.push(snap("saved"))
      p.editSummary = draftSummary
      p.editNext = draftNext
      p.dirty = true
      p.refresh()
      step = 5
      stepTicks = 0
      return
    }

    if (step === 5) {
      if (!idle())
        return
      if (p.current.summary !== expectedSummary) {
        fail("refresh clobbered published summary")
        return
      }
      if (p.editSummary !== draftSummary) {
        fail("refresh clobbered genuine in-progress summary draft")
        return
      }
      if (p.editNext !== draftNext) {
        fail("refresh clobbered genuine in-progress next draft")
        return
      }
      if (!p.dirty) {
        fail("refresh cleared genuine in-progress dirty flag")
        return
      }
      snapshots.push(snap("draft-preserved"))
      p.close()
      step = 6
      stepTicks = 0
      return
    }

    if (step === 6) {
      if (p.opened) {
        p.close()
        return
      }
      snapshots.push(snap("closed"))
      p.open()
      step = 7
      stepTicks = 0
      return
    }

    if (step === 7) {
      if (!p.opened)
        return
      if (!idle())
        return
      if (!p.hasCurrent || p.current.summary !== expectedSummary) {
        fail("close/open UI readback failed")
        return
      }
      if (p.editSummary !== draftSummary) {
        fail("open refresh clobbered genuine in-progress summary draft")
        return
      }
      snapshots.push(snap("reopened-open"))
      if (p.expanded)
        p.toggleView()
      step = 8
      stepTicks = 0
      return
    }

    if (step === 8) {
      if (!idle())
        return
      if (p.expanded || p.view !== "compact") {
        fail("did not collapse to compact")
        return
      }
      if (!p.hasCurrent || p.current.summary !== expectedSummary) {
        fail("compact view lost current checkpoint")
        return
      }
      snapshots.push(snap("compact"))
      panelLoader.active = false
      step = 9
      stepTicks = 0
      return
    }

    if (step === 9) {
      if (panelLoader.item)
        return
      panelLoader.active = true
      step = 10
      stepTicks = 0
      return
    }

    if (step === 10) {
      if (panelLoader.status === Loader.Error) {
        fail("Panel.qml failed to reload")
        return
      }
      if (panelLoader.status !== Loader.Ready || !panelObj())
        return
      step = 11
      stepTicks = 0
      return
    }

    if (step === 11) {
      p = panelObj()
      if (!idle())
        return
      if (stepTicks < 3)
        return
      if (!p.hasActivity || !p.hasCurrent) {
        fail("recreate load missing checkpoint")
        return
      }
      if (p.activity.id !== activityId) {
        fail("activity id changed across recreate")
        return
      }
      if (p.activity.name !== expectedName) {
        fail("activity name changed across recreate")
        return
      }
      if (p.current.summary !== expectedSummary) {
        fail("persisted UI summary mismatch")
        return
      }
      if (p.current.next_step !== expectedNext) {
        fail("persisted UI next mismatch")
        return
      }
      if (p.current.context !== expectedContext) {
        fail("persisted UI context mismatch")
        return
      }
      if (p.current.state !== expectedState) {
        fail("persisted UI state mismatch")
        return
      }
      if (p.current.author !== expectedAuthor) {
        fail("persisted UI author mismatch")
        return
      }
      if (p.editSummary !== expectedSummary) {
        fail("editor readback summary mismatch")
        return
      }
      if (p.editNext !== expectedNext) {
        fail("editor readback next mismatch")
        return
      }
      if (p.editContext !== expectedContext) {
        fail("editor readback context mismatch")
        return
      }
      if (p.editState !== expectedState) {
        fail("editor readback state mismatch")
        return
      }
      if (p.editAuthor !== expectedAuthor) {
        fail("editor readback author mismatch")
        return
      }
      if (p.dirty) {
        fail("fresh Panel marked dirty before any user edit")
        return
      }
      if (p.revision !== savedRevision) {
        fail("revision changed on reopen")
        return
      }
      if (p.lastError !== "") {
        fail("lastError set after recreate: " + p.lastError)
        return
      }
      snapshots.push(snap("recreated"))
      succeed()
    }
  }
}
