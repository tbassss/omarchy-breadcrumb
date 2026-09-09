import Quickshell
import Quickshell.Io
import QtQuick

// Isolated offscreen component driver for Breadcrumb #5 Panel.qml.
// Classification: real candidate Panel.qml + real qs/Qt runtime + minimal
// fake qs.Ui/qs.Commons. Not full omarchy-shell host integration.
//
// Retains #3 save/reopen/recreate and in-memory refresh, then durable
// draft recover, compact published+indicator, persist-then-switch,
// create-while-draft, and native conflict presentation via the store
// publish seam. Construction-time TextField onTextChanged must not be
// treated as a user draft.
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
  property string durableDraft: "Durable lantern draft after close"
  property string durableNext: "Keep this durable next step"
  property string secondSummary: "Mapped the east tunnel after the lantern count"
  property string secondNext: "Walk the restored checkpoint"
  property string activityBName: "App Project"
  property string activityBSummary: "Screen is ready for a hands-on check"
  property string activityBNext: "Walk the complete flow"
  property string activityId: ""
  property string activityBId: ""
  property string firstCheckpointId: ""
  property string restoredCheckpointId: ""
  property int savedRevision: 0
  property int restoredRevision: 0
  property int durableDraftRevision: 0
  property string dirtyCreateDraft: "Draft that must not vanish on create"
  property string agentSummary: "Agent published while the lantern draft was open"
  property string overlapNavDraft: "overlap-autosave-nav-v2"
  property string overlapSaveText: "explicit-save-behind-autosave"
  property string overlapDiscardText: "typed-during-discard"
  property bool externalDone: false
  property var qmlErrors: []

  function panelObj() {
    return panelLoader.item
  }

  function findActivityPicker(item) {
    if (!item)
      return null
    if (item.label === "Activity" && typeof item.selectCurrent === "function")
      return item
    var kids = item.children
    if (!kids)
      return null
    for (var i = 0; i < kids.length; i++) {
      var found = findActivityPicker(kids[i])
      if (found)
        return found
    }
    return null
  }

  function snap(tag) {
    var p = panelObj()
    if (!p)
      return { tag: tag, missing: true }
    var a = p.activity || null
    var c = p.current || null
    var history = p.historyEntries || []
    var acts = p.activities || []
    var picker = findActivityPicker(p)
    return {
      tag: tag,
      loadState: p.loadState,
      lastError: p.lastError,
      view: p.view,
      expanded: p.expanded,
      opened: p.opened,
      busy: p.busy,
      dirty: p.dirty,
      hasDraft: !!p.hasDraft,
      draftRevision: p.draftRevision || 0,
      draftStatus: p.draftStatus || "",
      conflictPrompt: !!p.conflictPrompt,
      draftBaseRevision: p.draftBaseRevision || 0,
      editSequence: p.editSequence || 0,
      observedRevision: p.observedRevision || 0,
      navBlockedReason: p.navBlockedReason || "",
      hasActivity: p.hasActivity,
      hasCurrent: p.hasCurrent,
      revision: p.revision,
      activityId: a ? a.id : "",
      activityName: a ? a.name : "",
      archivedAt: a && a.archived_at ? a.archived_at : "",
      summary: c ? c.summary : "",
      nextStep: c ? c.next_step : "",
      context: c ? c.context : "",
      state: c ? c.state : "",
      author: c ? c.author : "",
      savedAt: c ? c.saved_at : "",
      currentId: c ? c.id : "",
      editName: p.editName,
      editSummary: p.editSummary,
      editNext: p.editNext,
      editContext: p.editContext,
      editState: p.editState,
      editAuthor: p.editAuthor,
      activityCount: acts.length,
      historyCount: history.length,
      showArchived: !!p.showArchived,
      pickerValue: picker ? picker.value : "",
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
      activityBId: activityBId,
      firstCheckpointId: firstCheckpointId,
      restoredCheckpointId: restoredCheckpointId,
      savedRevision: savedRevision,
      restoredRevision: restoredRevision,
      qmlErrors: qmlErrors,
      classification: "component-test-not-full-host-integration",
      notes: "Real Panel.qml driven through createActivity/saveCheckpoint/saveDraft/switchActivity/archiveActivity/restoreCheckpoint, genuine in-memory draft refresh, Loader recreate of a durable draft, compact published+indicator, and native conflictPrompt after store publish. Host qs.Ui/qs.Commons are a minimal facade of inspected Cave APIs. KeyboardPanel is stubbed to avoid WlrLayershell. Not a live bar install."
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

  function writeOut(obj) {
    var json = JSON.stringify(obj)
    console.log("HARNESS_RESULT " + json)
    writer.command = ["/usr/bin/python3", "-c", "import os,sys; p=os.environ['BREADCRUMB_RESULTS']; open(p,'w',encoding='utf-8').write(sys.argv[1]); print('WROTE', p, len(sys.argv[1]))", json]
    writer.running = true
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

  Loader {
    id: panelLoader
    active: true
    source: pluginDir !== "" ? ("file://" + pluginDir + "/Panel.qml") : ""
  }

  Timer {
    interval: 120000
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

  function tick() {
    if (finished)
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
      firstCheckpointId = p.current.id
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
      if (!p.expanded)
        p.toggleView()
      step = 12
      stepTicks = 0
      return
    }

    if (step === 12) {
      if (!idle())
        return
      if (!p.expanded)
        return
      p.editSummary = durableDraft
      p.editNext = durableNext
      p.editContext = expectedContext
      p.editState = expectedState
      p.editAuthor = expectedAuthor
      p.saveDraft()
      step = 13
      stepTicks = 0
      return
    }

    if (step === 13) {
      if (!idle())
        return
      if (p.lastError !== "") {
        fail("saveDraft error: " + p.lastError)
        return
      }
      if (!p.hasDraft) {
        fail("saveDraft did not set hasDraft")
        return
      }
      if (p.draftStatus !== "saved") {
        fail("autosave acknowledgment was not honest: " + p.draftStatus)
        return
      }
      if ((p.historyEntries || []).length !== 1) {
        fail("saveDraft published history")
        return
      }
      durableDraftRevision = p.draftRevision
      snapshots.push(snap("durable-saved"))
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
        fail("did not collapse with durable draft")
        return
      }
      if (p.current.summary !== expectedSummary) {
        fail("compact showed draft text instead of published checkpoint")
        return
      }
      if (p.editSummary === expectedSummary && p.editSummary !== durableDraft) {
        fail("compact lost the durable editor draft")
        return
      }
      if (!p.hasDraft) {
        fail("compact missing unsaved draft indicator")
        return
      }
      snapshots.push(snap("compact-draft-indicator"))
      panelLoader.active = false
      step = 15
      stepTicks = 0
      return
    }

    if (step === 15) {
      if (panelLoader.item)
        return
      panelLoader.active = true
      step = 16
      stepTicks = 0
      return
    }

    if (step === 16) {
      if (panelLoader.status === Loader.Error) {
        fail("Panel.qml failed to reload with draft")
        return
      }
      if (panelLoader.status !== Loader.Ready || !panelObj())
        return
      step = 17
      stepTicks = 0
      return
    }

    if (step === 17) {
      p = panelObj()
      if (!idle())
        return
      if (stepTicks < 20)
        return
      if (!p.hasDraft) {
        fail("durable draft missing after recreate")
        return
      }
      if (p.current.summary !== expectedSummary) {
        fail("recreate with draft lost published checkpoint")
        return
      }
      if (p.editSummary !== durableDraft) {
        fail("durable draft missing after recreate")
        return
      }
      if (p.editNext !== durableNext) {
        fail("durable next missing after recreate")
        return
      }
      if ((p.historyEntries || []).length !== 1) {
        fail("recreate with draft published history")
        return
      }
      if (p.draftRevision !== durableDraftRevision) {
        fail("initial programmatic hydration accidentally autosaved")
        return
      }
      snapshots.push(snap("recreated-draft"))
      if (!p.expanded)
        p.toggleView()
      step = 18
      stepTicks = 0
      return
    }

    if (step === 18) {
      if (!idle())
        return
      p.editSummary = secondSummary
      p.editNext = secondNext
      p.editContext = expectedContext
      p.editState = expectedState
      p.editAuthor = expectedAuthor
      p.saveCheckpoint()
      step = 19
      stepTicks = 0
      return
    }

    if (step === 19) {
      if (!idle())
        return
      if (p.current.summary !== secondSummary) {
        fail("second A save summary mismatch")
        return
      }
      if (p.hasDraft) {
        fail("publish did not consume the matching draft")
        return
      }
      if (p.revision !== 2) {
        fail("second A save revision mismatch: " + p.revision)
        return
      }
      snapshots.push(snap("saved-a-second"))
      p.createName = activityBName
      p.createActivity()
      step = 20
      stepTicks = 0
      return
    }

    if (step === 20) {
      if (!idle())
        return
      if (!p.hasActivity || p.activity.name !== activityBName) {
        fail("createActivity B did not switch to App Project")
        return
      }
      if (p.activity.id === activityId) {
        fail("createActivity B reused activity A id")
        return
      }
      activityBId = p.activity.id
      snapshots.push(snap("created-b"))
      if (!p.expanded)
        p.toggleView()
      step = 21
      stepTicks = 0
      return
    }

    if (step === 21) {
      if (!idle())
        return
      p.editSummary = activityBSummary
      p.editNext = activityBNext
      p.editContext = expectedContext
      p.editState = expectedState
      p.editAuthor = expectedAuthor
      p.saveCheckpoint()
      step = 22
      stepTicks = 0
      return
    }

    if (step === 22) {
      if (!idle())
        return
      if (p.current.summary !== activityBSummary) {
        fail("B save summary mismatch")
        return
      }
      snapshots.push(snap("saved-b"))
      p.switchActivity(activityId)
      step = 23
      stepTicks = 0
      return
    }

    if (step === 23) {
      if (!idle())
        return
      if (p.activity.id !== activityId) {
        fail("switch to A failed")
        return
      }
      if (p.current.summary !== secondSummary) {
        fail("switch to A readback mismatch")
        return
      }
      if (p.editSummary !== secondSummary) {
        fail("switch to A did not hydrate editor")
        return
      }
      snapshots.push(snap("switched-a"))
      p.editSummary = "Unsaved A draft before switch"
      p.saveDraft()
      step = 24
      stepTicks = 0
      return
    }

    if (step === 24) {
      if (!idle())
        return
      if (!p.hasDraft) {
        fail("A draft did not persist before switch")
        return
      }
      p.switchActivity(activityBId)
      step = 25
      stepTicks = 0
      return
    }

    if (step === 25) {
      if (!idle())
        return
      if (p.activity.id !== activityBId) {
        fail("switch to B failed")
        return
      }
      if (p.current.summary !== activityBSummary) {
        fail("switch to B readback mismatch")
        return
      }
      snapshots.push(snap("switched-b"))
      p.switchActivity(activityId)
      step = 26
      stepTicks = 0
      return
    }

    if (step === 26) {
      if (!idle())
        return
      if (p.activity.id !== activityId) {
        fail("switch back to A lost the activity")
        return
      }
      if (p.editSummary !== "Unsaved A draft before switch") {
        fail("activity switch discarded A's durable draft")
        return
      }
      snapshots.push(snap("switched-a-draft-recovered"))
      panelLoader.active = false
      step = 27
      stepTicks = 0
      return
    }

    if (step === 27) {
      if (panelLoader.item)
        return
      panelLoader.active = true
      step = 28
      stepTicks = 0
      return
    }

    if (step === 28) {
      if (panelLoader.status === Loader.Error) {
        fail("Panel.qml failed to reload after B")
        return
      }
      if (panelLoader.status !== Loader.Ready || !panelObj())
        return
      step = 29
      stepTicks = 0
      return
    }

    if (step === 29) {
      p = panelObj()
      if (!idle())
        return
      if (stepTicks < 3)
        return
      if (p.activity.id !== activityId) {
        fail("activity id B mismatch after recreate")
        return
      }
      if (p.editSummary !== "Unsaved A draft before switch") {
        fail("recreate after switch lost A's durable draft")
        return
      }
      snapshots.push(snap("recreated-a-with-draft"))
      p.switchActivity(activityBId)
      step = 30
      stepTicks = 0
      return
    }

    if (step === 30) {
      if (!idle())
        return
      if (p.activity.id !== activityBId) {
        fail("activity id B mismatch after recreate")
        return
      }
      if (p.current.summary !== activityBSummary) {
        fail("B summary mismatch after recreate")
        return
      }
      snapshots.push(snap("switched-b-after-recreate"))
      p.archiveActivity(activityBId)
      step = 31
      stepTicks = 0
      return
    }

    if (step === 31) {
      if (!idle())
        return
      if (!p.activity || p.activity.id !== activityBId) {
        fail("archive switched away from B")
        return
      }
      if (!p.activity.archived_at) {
        fail("archive did not set archived_at")
        return
      }
      snapshots.push(snap("archived-b"))
      p.showArchived = true
      p.refresh()
      step = 32
      stepTicks = 0
      return
    }

    if (step === 32) {
      if (!idle())
        return
      if (p.activity.id !== activityBId || !p.activity.archived_at) {
        fail("archived activity was not readable")
        return
      }
      if (p.current.summary !== activityBSummary) {
        fail("archived B lost its checkpoint")
        return
      }
      snapshots.push(snap("archived-access"))
      p.switchActivity(activityId)
      step = 33
      stepTicks = 0
      return
    }

    if (step === 33) {
      if (!idle())
        return
      if (p.activity.id !== activityId) {
        fail("switch back to A after archive failed")
        return
      }
      if (p.current.summary !== secondSummary) {
        fail("A checkpoint mixed with B after archive")
        return
      }
      var history = p.historyEntries || []
      if (history.length < 2) {
        fail("A history missing dated pages")
        return
      }
      if (!firstCheckpointId) {
        fail("missing first checkpoint id")
        return
      }
      if (p.hasDraft) {
        if (!p.busy)
          p.discardDraft()
        return
      }
      snapshots.push(snap("history-before-restore"))
      p.restoreCheckpoint(firstCheckpointId)
      step = 34
      stepTicks = 0
      return
    }

    if (step === 34) {
      if (!idle())
        return
      if (p.lastError !== "") {
        fail("restore error: " + p.lastError)
        return
      }
      if (p.current.summary !== expectedSummary) {
        fail("restore did not bring first checkpoint forward")
        return
      }
      if (p.revision !== 3) {
        fail("restore did not append a new revision")
        return
      }
      if (p.current.id === firstCheckpointId) {
        fail("restore rewrote the original checkpoint id")
        return
      }
      restoredCheckpointId = p.current.id
      restoredRevision = p.revision
      var historyAfter = p.historyEntries || []
      if (historyAfter.length < 3) {
        fail("restore lost intervening history")
        return
      }
      snapshots.push(snap("restored"))
      step = 35
      stepTicks = 0
      return
    }

    if (step === 35) {
      if (!idle())
        return
      var picker = findActivityPicker(p)
      if (!picker) {
        fail("compact activityPicker not found")
        return
      }
      if (picker.value !== activityId) {
        fail("picker did not start on A: " + picker.value)
        return
      }
      snapshots.push(snap("picker-start-a"))
      p.editSummary = "Unsaved A draft before picker switch"
      p.saveDraft()
      step = 36
      stepTicks = 0
      return
    }

    if (step === 36) {
      if (!idle())
        return
      picker = findActivityPicker(p)
      if (!picker) {
        fail("compact activityPicker missing before picker switch")
        return
      }
      picker.selectCurrent(activityBId)
      step = 37
      stepTicks = 0
      return
    }

    if (step === 37) {
      if (!idle())
        return
      if (p.activity.id !== activityBId) {
        fail("picker completed switch did not land on B")
        return
      }
      picker = findActivityPicker(p)
      if (!picker) {
        fail("compact activityPicker missing after completed switch")
        return
      }
      if (picker.value !== activityBId) {
        fail("picker desync after completed switch")
        return
      }
      snapshots.push(snap("picker-completed-b"))
      p.switchActivity(activityId)
      step = 38
      stepTicks = 0
      return
    }

    if (step === 38) {
      if (!idle())
        return
      if (p.activity.id !== activityId) {
        fail("JS switch back to A failed")
        return
      }
      if (p.editSummary !== "Unsaved A draft before picker switch") {
        fail("picker switch discarded A's durable draft")
        return
      }
      picker = findActivityPicker(p)
      if (!picker) {
        fail("compact activityPicker missing after later activity change")
        return
      }
      if (picker.value !== activityId) {
        fail("picker desync after later activity change")
        return
      }
      snapshots.push(snap("picker-follow-a"))
      p.editSummary = dirtyCreateDraft
      p.saveDraft()
      step = 39
      stepTicks = 0
      return
    }

    if (step === 39) {
      if (!idle())
        return
      p.createName = "Personal"
      p.createActivity()
      step = 40
      stepTicks = 0
      return
    }

    if (step === 40) {
      if (!idle())
        return
      if (!p.activity || p.activity.name !== "Personal") {
        fail("create while draft did not create Personal")
        return
      }
      snapshots.push(snap("created-personal"))
      p.switchActivity(activityId)
      step = 41
      stepTicks = 0
      return
    }

    if (step === 41) {
      if (!idle())
        return
      if (!p.activity || p.activity.id !== activityId) {
        fail("create while draft could not return to A")
        return
      }
      if (p.editSummary !== dirtyCreateDraft) {
        fail("create while draft discarded A's durable draft")
        return
      }
      snapshots.push(snap("create-while-draft-preserved"))
      publishExternal(activityId, p.revision, agentSummary)
      step = 42
      stepTicks = 0
      return
    }

    if (step === 42) {
      if (!externalDone)
        return
      snapshots.push(snap("external-published"))
      panelLoader.active = false
      step = 43
      stepTicks = 0
      return
    }

    if (step === 43) {
      if (panelLoader.item)
        return
      panelLoader.active = true
      step = 44
      stepTicks = 0
      return
    }

    if (step === 44) {
      if (panelLoader.status === Loader.Error) {
        fail("Panel.qml failed to reload before old-base save")
        return
      }
      if (panelLoader.status !== Loader.Ready || !panelObj())
        return
      step = 45
      stepTicks = 0
      return
    }

    if (step === 45) {
      p = panelObj()
      if (!idle())
        return
      if (stepTicks < 20)
        return
      if (!p.hasDraft) {
        fail("recreate after external publish lost the draft")
        return
      }
      if (!p.current || p.current.summary !== agentSummary) {
        fail("recreate after external publish lost the newer publication")
        return
      }
      if (p.editSummary !== dirtyCreateDraft) {
        fail("recreate after external publish lost editor draft")
        return
      }
      snapshots.push(snap("recreated-old-base"))
      p.saveCheckpoint()
      step = 46
      stepTicks = 0
      return
    }

    if (step === 46) {
      if (!idle())
        return
      if (!p.conflictPrompt) {
        fail("recreate old-base save did not conflict")
        return
      }
      if (p.current.summary !== agentSummary) {
        fail("stale save overwrote the newer publication")
        return
      }
      if (p.editSummary !== dirtyCreateDraft) {
        fail("stale save blanked the draft")
        return
      }
      snapshots.push(snap("conflict"))
      p.resolveConflictKeepEditing()
      if (p.conflictPrompt) {
        fail("keep editing left the conflict prompt")
        return
      }
      snapshots.push(snap("conflict-keep"))
      p.saveCheckpoint()
      step = 47
      stepTicks = 0
      return
    }

    if (step === 47) {
      if (!idle())
        return
      if (!p.conflictPrompt) {
        fail("keep-editing retry overwrote publication")
        return
      }
      if (p.current.summary !== agentSummary) {
        fail("keep-editing retry overwrote the newer publication")
        return
      }
      if (p.editSummary !== dirtyCreateDraft) {
        fail("keep-editing retry lost the draft")
        return
      }
      snapshots.push(snap("conflict-keep-retry"))
      p.resolveConflictSave()
      step = 48
      stepTicks = 0
      return
    }

    if (step === 48) {
      if (!idle())
        return
      if (p.lastError !== "") {
        fail("resolution save error: " + p.lastError)
        return
      }
      if (p.conflictPrompt) {
        fail("resolution left the conflict prompt")
        return
      }
      if (p.current.summary !== dirtyCreateDraft) {
        fail("resolution did not publish the draft against the observed revision")
        return
      }
      if (p.hasDraft) {
        fail("resolution publish did not consume the draft")
        return
      }
      snapshots.push(snap("conflict-resolved"))
      if (!p.expanded)
        p.toggleView()
      if (!p.showArchived)
        p.toggleArchived()
      step = 49
      stepTicks = 0
      return
    }

    if (step === 49) {
      if (!idle())
        return
      p.editSummary = "overlap-autosave-nav-v1"
      p.markUserEdit()
      p.saveDraft()
      p.editSummary = overlapNavDraft
      p.markUserEdit()
      p.switchActivity(activityBId)
      step = 50
      stepTicks = 0
      return
    }

    if (step === 50) {
      if (!idle())
        return
      if (p.editSummary === "overlap-autosave-nav-v1" && p.activity.id === activityId) {
        fail("delayed autosave ack dropped newer keystrokes")
        return
      }
      if (p.activity.id === activityBId) {
        p.switchActivity(activityId)
        step = 51
        stepTicks = 0
        return
      }
      if (p.activity.id !== activityId) {
        fail("overlap-autosave-nav left an unexpected activity")
        return
      }
      if (p.navBlockedReason && p.navBlockedReason !== "")
        return
      p.switchActivity(activityBId)
      step = 51
      stepTicks = 0
      return
    }

    if (step === 51) {
      if (!idle())
        return
      if (p.activity.id === activityBId) {
        p.switchActivity(activityId)
        return
      }
      if (p.activity.id !== activityId) {
        fail("overlap-autosave-nav could not return to A")
        return
      }
      if (p.editSummary !== overlapNavDraft) {
        fail("overlap-autosave-nav lost newer keystrokes: " + p.editSummary)
        return
      }
      snapshots.push(snap("overlap-autosave-nav"))
      p.editSummary = "queued-autosave"
      p.markUserEdit()
      p.saveDraft()
      p.editSummary = overlapSaveText
      p.markUserEdit()
      p.saveCheckpoint()
      p.editSummary = overlapSaveText
      p.markUserEdit()
      p.saveDraft()
      step = 52
      stepTicks = 0
      return
    }

    if (step === 52) {
      if (!idle())
        return
      if (p.current.summary !== overlapSaveText) {
        fail("explicit save behind autosave was dropped")
        return
      }
      snapshots.push(snap("explicit-save-behind-autosave"))
      p.editSummary = "draft-before-discard"
      p.markUserEdit()
      p.saveDraft()
      step = 53
      stepTicks = 0
      return
    }

    if (step === 53) {
      if (!idle())
        return
      p.discardDraft()
      p.editSummary = overlapDiscardText
      p.markUserEdit()
      step = 54
      stepTicks = 0
      return
    }

    if (step === 54) {
      if (!idle())
        return
      if (p.editSummary !== overlapDiscardText) {
        fail("obsolete discard clobbered editor")
        return
      }
      if (p.current.summary !== overlapSaveText) {
        fail("obsolete discard mutated the published checkpoint")
        return
      }
      snapshots.push(snap("obsolete-discard-protected"))
      succeed()
    }
  }
}
