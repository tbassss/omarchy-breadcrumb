import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Named activities + dated history + crash-safe drafts + public agent command (#6).
// Compact shows the published checkpoint and a draft indicator. Expanded
// edits the draft. UI persistence is breadcrumb-store via Process argv.
// Agents use bin/breadcrumb stdin JSON. Stale Save never overwrites.
Panel {
  id: root
  moduleName: "tbassss.breadcrumb"
  ipcTarget: "tbassss.breadcrumb"

  property string loadState: "loading"
  property string lastError: ""
  property var activity: null
  property var current: null
  property int revision: 0
  property string view: "compact"
  property string pendingAction: ""
  property var pendingOpen: null
  property var pendingMeta: ({})
  property bool dirty: false // genuine user edits (onTextEdited); construction onTextChanged is not a draft
  property bool hydrating: false
  property bool hasDraft: false
  property int draftRevision: 0
  property int draftBaseRevision: 0
  property string draftStatus: ""
  property int autosaveGeneration: 0
  property bool pendingAutosave: false
  property bool conflictPrompt: false
  property var deleteConfirm: null
  property int observedRevision: 0
  property int editSequence: 0
  property int requestIdCounter: 0
  property var opQueue: []
  property var inFlight: null
  property string navBlockedReason: ""
  property string pendingSwitchAfterDraft: ""
  property bool pendingCreateAfterDraft: false
  property string editName: ""
  property string createName: ""
  property string renameName: ""
  property string editSummary: ""
  property string editNext: ""
  property string editContext: ""
  property string editState: "ready"
  property string editAuthor: "You"
  property var activities: []
  property var historyEntries: []
  property bool historyHasMore: false
  property var historyNextBefore: null
  property bool showArchived: false
  property var lastOpenArgv: []
  property int contentWidthHint: 0
  property bool openLaunchStarted: false
  property int openLaunchExitCode: 0
  property string openLaunchState: ""
  property bool cursorActive: false
  property int cursorIndex: 0
  property int editorFocusCount: 0
  property int openPopupCount: 0
  property int catcherActivateCount: 0

  readonly property bool busy: storeProc.running
  readonly property bool openProcRunning: openProc.running
  readonly property bool expanded: root.view === "expanded"
  readonly property bool hasActivity: !!(root.activity && root.activity.id)
  readonly property bool hasCurrent: !!(root.current && root.current.id)
  readonly property string storePath: Model.fileFromUrl(Qt.resolvedUrl("bin/breadcrumb-store"))
  readonly property string commandPath: Model.fileFromUrl(Qt.resolvedUrl("bin/breadcrumb"))
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property color muted: Color.muted
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property bool narrow: column.width < Style.space(560)
  readonly property bool catcherBlocked: root.editorFocusCount > 0 || root.openPopupCount > 0

  function buildActivityOptions() {
    var opts = []
    var seen = {}
    var acts = root.activities || []
    for (var i = 0; i < acts.length; i++) {
      var item = acts[i]
      if (!item || !item.id)
        continue
      seen[item.id] = true
      opts.push({ value: item.id, label: root.activityLabel(item) })
    }
    if (root.activity && root.activity.id && !seen[root.activity.id])
      opts.unshift({ value: root.activity.id, label: root.activityLabel(root.activity) })
    return opts
  }

  function activityLabel(item) {
    var name = item && item.name ? String(item.name) : ""
    if (item && item.archived_at)
      return name + " (archived)"
    return name
  }

  function beginHydrate() {
    root.hydrating = true
  }

  function endHydrate() {
    Qt.callLater(function() { root.hydrating = false })
  }

  function applyPublishedFields(body) {
    root.activity = body.activity || null
    if (body.current !== undefined)
      root.current = body.current || null
    if (body.revision !== undefined)
      root.revision = body.revision || 0
    if (body.view === "compact" || body.view === "expanded")
      root.view = body.view
    if (body.activities)
      root.activities = body.activities
    if (body.history) {
      root.historyEntries = body.history.entries || []
      root.historyHasMore = !!body.history.has_more
      root.historyNextBefore = body.history.next_before_revision
    }
    if (body.state === "empty")
      root.loadState = "empty"
    else
      root.loadState = "ready"
    if (root.hasActivity) {
      root.editName = root.activity.name || ""
      root.renameName = root.activity.name || ""
    }
  }

  function applyDraftToEditor(draft) {
    root.editSummary = draft.summary || ""
    root.editNext = draft.next_step || ""
    root.editContext = draft.context || ""
    root.editState = draft.state || "ready"
    root.editAuthor = draft.author || Model.defaultAuthor()
    linkModel.clear()
    var links = draft.links || []
    for (var i = 0; i < links.length; i++) {
      linkModel.append({
        label: links[i].label || "",
        kind: links[i].kind || "web",
        target: links[i].target || ""
      })
    }
  }

  function hydrateEditorFromSnapshot(body) {
    beginHydrate()
    var draft = body.draft
    if (draft) {
      applyDraftToEditor(draft)
      root.hasDraft = true
      root.draftRevision = draft.revision || 0
      root.draftBaseRevision = draft.base_revision || 0
      root.dirty = true
      root.pendingAutosave = false
      root.draftStatus = "saved"
    } else {
      copyCurrentToEditor()
      root.hasDraft = false
      root.draftRevision = body.draft_generation || 0
      root.draftBaseRevision = root.revision
      root.dirty = false
      root.pendingAutosave = false
      root.draftStatus = ""
    }
    endHydrate()
  }

  function applySnapshot(body) {
    var previousId = root.activity && root.activity.id ? root.activity.id : ""
    applyPublishedFields(body)
    var newId = root.activity && root.activity.id ? root.activity.id : ""
    var activityChanged = newId !== previousId
    if (activityChanged)
      root.conflictPrompt = false
    if (activityChanged)
      root.deleteConfirm = null
    if (activityChanged || (!root.pendingAutosave && !root.dirty))
      hydrateEditorFromSnapshot(body)
    root.noteExternalPublication(body)
    root.syncActivityPicker()
    Qt.callLater(function() { root.revealSelectedActivity() })
  }

  function noteExternalPublication(body) {
    var published = body.revision || 0
    var local = root.hasDraft || root.dirty || root.pendingAutosave
    if (local && published > root.draftBaseRevision) {
      root.conflictPrompt = true
      root.observedRevision = published
    }
  }

  function syncActivityPicker() {
    if (!activityPicker)
      return
    var id = root.activity && root.activity.id ? String(root.activity.id) : ""
    activityPicker.value = id
  }

  function copyCurrentToEditor() {
    beginHydrate()
    if (!root.hasCurrent) {
      root.editSummary = ""
      root.editNext = ""
      root.editContext = ""
      root.editState = "ready"
      root.editAuthor = Model.defaultAuthor()
      linkModel.clear()
      endHydrate()
      return
    }
    root.editSummary = root.current.summary || ""
    root.editNext = root.current.next_step || ""
    root.editContext = root.current.context || ""
    root.editState = root.current.state || "ready"
    root.editAuthor = root.current.author || Model.defaultAuthor()
    linkModel.clear()
    var links = root.current.links || []
    for (var i = 0; i < links.length; i++) {
      linkModel.append({
        label: links[i].label || "",
        kind: links[i].kind || "web",
        target: links[i].target || ""
      })
    }
    endHydrate()
  }

  function collectLinks() {
    var links = []
    for (var i = 0; i < linkModel.count; i++) {
      var row = linkModel.get(i)
      var label = String(row.label || "").trim()
      var target = String(row.target || "").trim()
      if (!label && !target)
        continue
      links.push({ label: label, kind: String(row.kind || "web"), target: target })
    }
    return links
  }

  function markUserEdit() {
    if (root.hydrating)
      return
    if (!root.hasDraft)
      root.draftBaseRevision = root.revision
    root.editSequence += 1
    root.dirty = true
    root.hasDraft = true
    root.pendingAutosave = true
    root.draftStatus = ""
    scheduleAutosave()
  }

  function scheduleAutosave() {
    if (root.hydrating || !root.hasActivity)
      return
    autosaveTimer.restart()
  }

  function editorDraftPayload() {
    return {
      activity_id: root.activity.id,
      summary: root.editSummary,
      next_step: root.editNext,
      context: root.editContext,
      state: root.editState,
      author: root.editAuthor || Model.defaultAuthor(),
      links: collectLinks()
    }
  }

  function saveDraft() {
    if (!root.hasActivity)
      return
    autosaveTimer.stop()
    root.draftStatus = "saving"
    runStore("save-draft", editorDraftPayload(), { editSequence: root.editSequence, activityId: root.activity.id })
  }

  function discardDraft() {
    if (!root.hasActivity)
      return
    autosaveTimer.stop()
    dropUnsentAutosaves(root.activity.id)
    root.pendingAutosave = false
    root.pendingSwitchAfterDraft = ""
    root.pendingCreateAfterDraft = false
    root.navBlockedReason = ""
    runStore("discard-draft", { activity_id: root.activity.id }, { editSequence: root.editSequence, activityId: root.activity.id })
  }

  function abortPendingNav() {
    root.pendingSwitchAfterDraft = ""
    root.pendingCreateAfterDraft = false
    root.navBlockedReason = ""
    root.syncActivityPicker()
  }

  function dropUnsentAutosaves(activityId) {
    var kept = []
    for (var i = 0; i < root.opQueue.length; i++) {
      var op = root.opQueue[i]
      if (!(op.action === "save-draft" && op.activityId === activityId))
        kept.push(op)
    }
    root.opQueue = kept
  }

  function hasUnsentAutosave(activityId) {
    for (var i = 0; i < root.opQueue.length; i++) {
      if (root.opQueue[i].action === "save-draft" && root.opQueue[i].activityId === activityId)
        return true
    }
    return false
  }

  function enqueueOp(op) {
    if (op.action === "save-draft") {
      for (var i = 0; i < root.opQueue.length; i++) {
        if (root.opQueue[i].action === "save-draft" && root.opQueue[i].activityId === op.activityId) {
          root.opQueue[i] = op
          pumpQueue()
          return
        }
      }
    }
    root.opQueue.push(op)
    pumpQueue()
  }

  function pumpQueue() {
    if (storeProc.running || root.inFlight)
      return
    if (!root.opQueue.length)
      return
    var next = root.opQueue[0]
    var rest = []
    for (var i = 1; i < root.opQueue.length; i++)
      rest.push(root.opQueue[i])
    root.opQueue = rest
    sendOp(next)
  }

  function sendOp(op) {
    var payload = op.payload || {}
    if (op.action === "save-draft") {
      payload.expected_draft_revision = root.draftRevision
      payload.base_revision = root.draftBaseRevision
      if (op.activityId === (root.activity ? root.activity.id : "")) {
        payload.summary = root.editSummary
        payload.next_step = root.editNext
        payload.context = root.editContext
        payload.state = root.editState
        payload.author = root.editAuthor || Model.defaultAuthor()
        payload.links = collectLinks()
        op.editSequence = root.editSequence
      }
    } else if (op.action === "discard-draft") {
      payload.expected_draft_revision = root.draftRevision
    } else if (op.action === "publish") {
      if (op.activityId === (root.activity ? root.activity.id : "")) {
        payload.summary = root.editSummary
        payload.next_step = root.editNext
        payload.context = root.editContext
        payload.state = root.editState
        payload.author = root.editAuthor || Model.defaultAuthor()
        payload.links = collectLinks()
      }
      if (op.resolve)
        payload.expected_revision = root.observedRevision
      else if (root.hasDraft || root.dirty)
        payload.expected_revision = root.draftBaseRevision
      else
        payload.expected_revision = root.revision
      if (root.hasDraft)
        payload.consume_draft_revision = root.draftRevision
      else
        delete payload.consume_draft_revision
    }
    op.payload = payload
    root.inFlight = op
    root.pendingAction = op.action
    root.pendingMeta = op
    if (root.loadState !== "error")
      root.loadState = root.loadState === "ready" || root.loadState === "empty" ? root.loadState : "loading"
    if (op.action === "get" && !root.hasCurrent && !root.hasActivity)
      root.loadState = "loading"
    storeProc.command = ["/usr/bin/python3", root.storePath, op.action, JSON.stringify(payload || {})]
    storeProc.running = true
  }

  function runStore(action, payload, meta) {
    meta = meta || {}
    enqueueOp({
      requestId: ++root.requestIdCounter,
      action: action,
      kind: action,
      activityId: meta.activityId || (root.activity ? root.activity.id : ""),
      editSequence: meta.editSequence !== undefined ? meta.editSequence : root.editSequence,
      payload: payload || {},
      resolve: !!meta.resolve
    })
  }

  function refresh() {
    var payload = { include_archived: root.showArchived }
    if (root.activity && root.activity.id)
      payload.activity_id = root.activity.id
    runStore("get", payload)
  }

  function probeExternal() {
    if (!root.opened || !root.hasActivity)
      return
    if (probeProc.running || storeProc.running || root.inFlight)
      return
    probeProc.command = ["/usr/bin/python3", root.storePath, "head", JSON.stringify({ activity_id: root.activity.id })]
    probeProc.running = true
  }

  function handleProbe(raw) {
    var body = Model.parseResponse(raw)
    if (!body.ok)
      return
    var rev = body.revision || 0
    var cid = body.checkpoint_id || ""
    var currentId = root.current && root.current.id ? root.current.id : ""
    if (rev === root.revision && cid === currentId)
      return
    if (root.busy || storeProc.running)
      return
    root.refresh()
  }

  function actuallyCreate() {
    var name = String(root.createName || "").trim()
    if (!name)
      name = String(root.editName || "").trim()
    runStore("create-activity", { name: name })
  }

  function createActivity() {
    if (root.pendingAutosave || root.dirty) {
      root.pendingCreateAfterDraft = true
      root.navBlockedReason = "Saving draft…"
      saveDraft()
      return
    }
    actuallyCreate()
  }

  function saveCheckpoint() {
    if (!root.hasActivity)
      return
    autosaveTimer.stop()
    var payload = editorDraftPayload()
    payload.expected_revision = (root.hasDraft || root.dirty) ? root.draftBaseRevision : root.revision
    if (root.hasDraft)
      payload.consume_draft_revision = root.draftRevision
    runStore("publish", payload, {
      editSequence: root.editSequence,
      activityId: root.activity.id,
      resolve: false
    })
  }

  function needsDraftFlush() {
    if (!root.hasActivity)
      return false
    if (root.dirty || root.pendingAutosave)
      return true
    if (root.inFlight && root.inFlight.action === "save-draft" && root.inFlight.activityId === root.activity.id)
      return true
    return hasUnsentAutosave(root.activity.id)
  }

  function switchActivity(id) {
    if (!id)
      return
    if (root.activity && id === root.activity.id) {
      root.pendingSwitchAfterDraft = ""
      root.navBlockedReason = ""
      root.syncActivityPicker()
      return
    }
    if (needsDraftFlush()) {
      root.pendingSwitchAfterDraft = id
      root.navBlockedReason = "Saving draft…"
      root.draftStatus = "saving"
      saveDraft()
      root.syncActivityPicker()
      return
    }
    doSwitch(id)
  }

  function doSwitch(id) {
    root.deleteConfirm = null
    autosaveTimer.stop()
    root.pendingSwitchAfterDraft = ""
    root.navBlockedReason = ""
    runStore("get", { activity_id: id, include_archived: root.showArchived })
  }

  function resolveConflictSave() {
    root.conflictPrompt = false
    if (!root.hasActivity)
      return
    autosaveTimer.stop()
    var payload = editorDraftPayload()
    payload.expected_revision = root.observedRevision
    if (root.hasDraft)
      payload.consume_draft_revision = root.draftRevision
    runStore("publish", payload, {
      editSequence: root.editSequence,
      activityId: root.activity.id,
      resolve: true
    })
  }

  function resolveConflictLoadPublished() {
    root.conflictPrompt = false
    discardDraft()
  }

  function resolveConflictKeepEditing() {
    root.conflictPrompt = false
  }

  function renameActivity() {
    if (!root.hasActivity)
      return
    runStore("rename-activity", { activity_id: root.activity.id, name: root.renameName })
  }

  function archiveActivity(id) {
    var target = id || (root.activity ? root.activity.id : "")
    if (!target)
      return
    root.deleteConfirm = null
    runStore("archive-activity", { activity_id: target })
  }

  function requestDeleteArchived() {
    if (root.busy || !root.hasActivity || !root.activity.archived_at)
      return
    root.deleteConfirm = {
      activity_id: String(root.activity.id),
      expected_name: String(root.activity.name || ""),
      expected_archived_at: String(root.activity.archived_at),
      expected_revision: root.revision,
      expected_draft_revision: root.draftRevision
    }
  }

  function cancelDeleteArchived() {
    root.deleteConfirm = null
  }

  function confirmDeleteArchived() {
    if (root.busy || !root.deleteConfirm)
      return
    var frozen = root.deleteConfirm
    root.deleteConfirm = null
    dropUnsentAutosaves(frozen.activity_id)
    runStore("delete-archived-activity", {
      activity_id: frozen.activity_id,
      expected_revision: frozen.expected_revision,
      expected_draft_revision: frozen.expected_draft_revision,
      expected_archived_at: frozen.expected_archived_at,
      expected_name: frozen.expected_name
    }, { activityId: frozen.activity_id })
  }

  function restoreCheckpoint(checkpointId) {
    if (!root.hasActivity || !checkpointId)
      return
    if (root.dirty || root.hasDraft) {
      root.lastError = "Save or discard the current edit before restoring history."
      return
    }
    runStore("restore", {
      activity_id: root.activity.id,
      checkpoint_id: checkpointId,
      expected_revision: root.revision
    })
  }

  function loadMoreHistory() {
    if (!root.hasActivity || !root.historyHasMore)
      return
    runStore("history", {
      activity_id: root.activity.id,
      limit: 20,
      before_revision: root.historyNextBefore
    })
  }

  function toggleArchived() {
    root.deleteConfirm = null
    root.showArchived = !root.showArchived
    refresh()
  }

  function toggleView() {
    var next = root.expanded ? "compact" : "expanded"
    root.view = next
    runStore("set-view", { view: next })
  }

  function openValidatedLink(kind, target) {
    root.pendingOpen = { kind: kind, target: target }
    root.lastOpenArgv = []
    runStore("validate-link", { kind: kind, target: target })
  }

  function launchOpenArgv(argv) {
    root.lastOpenArgv = argv
    var cmd = root.resolveOpenArgv(argv)
    if (!cmd.length)
      return
    root.startOpenProcess(cmd)
  }

  function resolveOpenArgv(argv) {
    if (!argv || !argv.length)
      return []
    var copy = []
    for (var i = 0; i < argv.length; i++)
      copy.push(String(argv[i]))
    var launcher = Quickshell.env("BREADCRUMB_OPEN_LAUNCHER")
    if (launcher && String(launcher).length)
      copy[0] = String(launcher)
    else if (Quickshell.env("BREADCRUMB_NO_OPEN") === "1" && copy[0] === "xdg-open")
      return []
    return copy
  }

  function startOpenProcess(cmd) {
    if (openProc.running)
      openProc.running = false
    root.openLaunchStarted = false
    root.openLaunchExitCode = 0
    root.openLaunchState = "starting"
    openProc.command = cmd
    openProc.running = true
    openTimeout.restart()
    Qt.callLater(function() {
      if (root.openLaunchState === "starting" && !openProc.running && !root.openLaunchStarted)
        root.noteOpenLaunchFailure()
    })
  }

  function noteOpenLaunchFailure() {
    root.lastError = "Could not open that link."
    root.openLaunchState = "failed"
    openTimeout.stop()
  }

  function noteEditorFocus(focused) {
    root.editorFocusCount += focused ? 1 : -1
    if (root.editorFocusCount < 0)
      root.editorFocusCount = 0
  }

  function notePopup(open) {
    root.openPopupCount += open ? 1 : -1
    if (root.openPopupCount < 0)
      root.openPopupCount = 0
  }

  function elidedLabel(text, maxChars) {
    var s = String(text || "")
    var limit = maxChars || 28
    if (s.length <= limit)
      return s
    return s.slice(0, Math.max(1, limit - 1)) + "…"
  }

  function collectLabeledButtons(item, labels, out) {
    if (!item || item.visible === false)
      return
    var label = item.text !== undefined ? String(item.text) : ""
    if (labels.indexOf(label) >= 0 && item.focusable)
      out.push(item)
    var kids = item.children
    if (!kids)
      return
    for (var i = 0; i < kids.length; i++)
      collectLabeledButtons(kids[i], labels, out)
  }

  function keyboardTargets() {
    var t = []
    if (expandButton && expandButton.visible && expandButton.focusable)
      t.push(expandButton)
    if (!root.expanded) {
      if (activityPicker && activityPicker.visible)
        t.push(activityPicker)
      return t
    }
    if (statePicker && statePicker.visible)
      t.push(statePicker)
    if (summaryField && summaryField.visible)
      t.push(summaryField)
    if (nextField && nextField.visible)
      t.push(nextField)
    if (contextArea && contextArea.visible)
      t.push(contextArea)
    var extras = []
    collectLabeledButtons(expandedEditor, ["Open", "Add link", "Save checkpoint", "Restore", "Older"], extras)
    for (var i = 0; i < extras.length; i++) {
      if (t.indexOf(extras[i]) < 0)
        t.push(extras[i])
    }
    return t
  }

  function applyCursorHighlight() {
    var t = root.keyboardTargets()
    for (var i = 0; i < t.length; i++) {
      if (t[i] && t[i].hasCursor !== undefined)
        t[i].hasCursor = (root.cursorActive && i === root.cursorIndex)
    }
  }

  function revealItem(item) {
    if (!item || !panelScroller)
      return
    var mapped = item.mapToItem(panelScroller.contentItem, 0, 0)
    var y = mapped.y
    var h = Math.max(1, item.height)
    var top = panelScroller.contentY
    var view = panelScroller.height
    var pad = Style.space(8)
    if (y < top)
      panelScroller.contentY = Math.max(0, y - pad)
    else if (y + h > top + view)
      panelScroller.contentY = Math.max(0, Math.min(panelScroller.contentHeight - view, y + h - view + pad))
  }

  function revealSelectedActivity() {
    if (!activityScroller || !activityList)
      return
    var kids = activityList.children
    for (var i = 0; i < kids.length; i++) {
      var btn = kids[i]
      if (!btn || !btn.selected)
        continue
      var y = btn.y
      var h = Math.max(1, btn.height)
      if (y < activityScroller.contentY)
        activityScroller.contentY = Math.max(0, y)
      else if (y + h > activityScroller.contentY + activityScroller.height)
        activityScroller.contentY = Math.max(0, y + h - activityScroller.height)
      return
    }
  }

  function moveKeyboardCursor(dx, dy) {
    var t = root.keyboardTargets()
    if (!t.length)
      return
    if (!root.cursorActive) {
      root.cursorActive = true
      if (root.cursorIndex < 0 || root.cursorIndex >= t.length)
        root.cursorIndex = 0
      root.applyCursorHighlight()
      root.revealItem(t[root.cursorIndex])
      return
    }
    var delta = dy !== 0 ? dy : dx
    root.cursorIndex = Math.max(0, Math.min(t.length - 1, root.cursorIndex + delta))
    root.applyCursorHighlight()
    root.revealItem(t[root.cursorIndex])
  }

  function activateKeyboardCursor() {
    var t = root.keyboardTargets()
    if (!t.length)
      return
    if (root.cursorIndex < 0 || root.cursorIndex >= t.length)
      root.cursorIndex = 0
    var item = t[root.cursorIndex]
    root.cursorActive = true
    root.applyCursorHighlight()
    if (!item)
      return
    if (item === expandButton) {
      if (root.busy || !expandButton.focusable)
        return
      root.toggleView()
      return
    }
    if (item === activityPicker && activityPicker.toggle) {
      activityPicker.toggle()
      return
    }
    if (item === statePicker && statePicker.toggle) {
      statePicker.toggle()
      root.revealItem(item)
      return
    }
    if (item === saveCheckpointButton) {
      if (!root.busy && saveCheckpointButton.focusable)
        root.saveCheckpoint()
      return
    }
    var label = item.text !== undefined ? String(item.text) : ""
    if (label === "Add link" || label === "Open" || label === "Restore" || label === "Older") {
      item.clicked()
      root.revealItem(item)
      return
    }
    if (item.forceActiveFocus)
      item.forceActiveFocus()
    root.revealItem(item)
  }

  function clearDraftState() {
    root.hasDraft = false
    root.draftBaseRevision = root.revision
    root.pendingAutosave = false
    root.draftStatus = ""
    root.dirty = false
    root.conflictPrompt = false
    root.navBlockedReason = ""
  }

  function maybeFinishDeferredNav() {
    if (root.pendingSwitchAfterDraft) {
      if (root.dirty || root.pendingAutosave)
        return false
      var switchId = root.pendingSwitchAfterDraft
      root.pendingSwitchAfterDraft = ""
      root.navBlockedReason = ""
      Qt.callLater(function() { root.doSwitch(switchId) })
      return true
    }
    if (root.pendingCreateAfterDraft) {
      if (root.dirty || root.pendingAutosave)
        return false
      root.pendingCreateAfterDraft = false
      root.navBlockedReason = ""
      Qt.callLater(function() { root.actuallyCreate() })
      return true
    }
    return false
  }

  function handleStoreResult(exitCode, raw) {
    var body = Model.parseResponse(raw)
    var op = root.inFlight || root.pendingMeta || {}
    var action = op.action || root.pendingAction
    root.inFlight = null
    if (!body.ok) {
      root.lastError = body.message || "Could not complete that action."
      if (action === "save-draft") {
        root.draftStatus = "error"
        abortPendingNav()
      }
      if (action === "publish" && body.error === "stale_revision") {
        root.conflictPrompt = true
        if (body.current_revision !== undefined)
          root.observedRevision = body.current_revision
        Qt.callLater(function() { root.refresh() })
      }
      if (action === "get") {
        if (!(root.hasCurrent || root.hasActivity))
          root.loadState = "error"
      } else if (action !== "set-view" && root.loadState === "loading" && !(root.hasCurrent || root.hasActivity)) {
        root.loadState = "error"
      }
      root.syncActivityPicker()
      return
    }
    root.lastError = ""
    if (action === "save-draft") {
      var sameActivity = op.activityId && root.activity && op.activityId === root.activity.id
      if (sameActivity && body.draft) {
        root.draftRevision = body.draft.revision || 0
        root.draftBaseRevision = body.draft.base_revision || root.draftBaseRevision
        root.hasDraft = true
        if (op.editSequence === root.editSequence) {
          root.pendingAutosave = false
          root.draftStatus = "saved"
          root.dirty = false
        } else {
          root.pendingAutosave = true
          root.draftStatus = ""
          Qt.callLater(function() { root.saveDraft() })
        }
      }
      maybeFinishDeferredNav()
      return
    }
    if (action === "discard-draft") {
      if (body.draft_generation !== undefined)
        root.draftRevision = body.draft_generation
      var discardSameActivity = op.activityId && root.activity && op.activityId === root.activity.id
      if (!discardSameActivity)
        return
      if (op.editSequence !== root.editSequence) {
        root.hasDraft = true
        root.dirty = true
        root.pendingAutosave = true
        Qt.callLater(function() { root.saveDraft() })
        return
      }
      beginHydrate()
      root.hasDraft = false
      root.draftBaseRevision = root.revision
      root.pendingAutosave = false
      root.draftStatus = ""
      root.dirty = false
      root.conflictPrompt = false
      copyCurrentToEditor()
      return
    }
    if (action === "create-activity") {
      root.createName = ""
      clearDraftState()
      applySnapshot({
        activity: body.activity || null,
        current: null,
        revision: 0,
        state: "empty",
        view: root.view,
        draft: null,
        draft_generation: 0
      })
      if (root.hasActivity) {
        Qt.callLater(function() {
          root.runStore("get", { activity_id: root.activity.id, include_archived: root.showArchived })
        })
      }
      return
    }
    if (action === "get") {
      applySnapshot(body)
      return
    }
    if (action === "publish" || action === "restore") {
      if (action === "publish") {
        if (body.draft_generation !== undefined)
          root.draftRevision = body.draft_generation
        clearDraftState()
      }
      applySnapshot({
        activity: root.activity,
        current: body.current || null,
        revision: body.revision,
        view: root.view,
        state: body.state,
        draft: null,
        draft_generation: root.draftRevision
      })
      Qt.callLater(function() { root.refresh() })
      return
    }
    if (action === "rename-activity" || action === "archive-activity") {
      if (body.activity && root.activity && body.activity.id === root.activity.id)
        root.activity = body.activity
      Qt.callLater(function() { root.refresh() })
      return
    }
    if (action === "delete-archived-activity") {
      root.deleteConfirm = null
      dropUnsentAutosaves(op.activityId)
      clearDraftState()
      Qt.callLater(function() {
        if (body.selected_activity_id)
          root.runStore("get", { activity_id: body.selected_activity_id, include_archived: root.showArchived })
        else
          root.runStore("get", { include_archived: root.showArchived })
      })
      return
    }
    if (action === "history") {
      var extra = body.entries || []
      var combined = (root.historyEntries || []).slice()
      for (var i = 0; i < extra.length; i++)
        combined.push(extra[i])
      root.historyEntries = combined
      root.historyHasMore = !!body.has_more
      root.historyNextBefore = body.next_before_revision
      return
    }
    if (action === "set-view") {
      if (body.view === "compact" || body.view === "expanded")
        root.view = body.view
      return
    }
    if (action === "validate-link" && body.open_argv && body.open_argv.length)
      root.launchOpenArgv(body.open_argv)
  }

  onOpenedChanged: if (opened) refresh()
  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  ListModel { id: linkModel }

  Timer {
    id: autosaveTimer
    interval: 250
    repeat: false
    onTriggered: root.saveDraft()
  }

  Timer {
    id: changeProbe
    interval: 750
    repeat: true
    running: root.opened
    onTriggered: root.probeExternal()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: Component {
      Canvas {
        property color ink: button.active ? button.activeColor : button.foreground
        onInkChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
          var c = getContext("2d")
          c.reset()
          c.scale(width / 24, height / 24)
          c.strokeStyle = ink
          c.fillStyle = ink
          c.lineWidth = 1.8
          c.lineJoin = "round"
          c.lineCap = "round"
          // Rounded toast outline with two distinct bite scallops.
          c.beginPath()
          c.moveTo(5, 19.5)
          c.lineTo(5, 11.5)
          c.bezierCurveTo(0.5, 10, 2.5, 4, 8, 3.5)
          c.bezierCurveTo(12, 2.5, 15.5, 3, 17.5, 5)
          c.bezierCurveTo(13.5, 5, 13.5, 9, 17, 9.5)
          c.bezierCurveTo(13.5, 11, 15, 14.5, 18.5, 14)
          c.lineTo(18.5, 19.5)
          c.quadraticCurveTo(12, 21, 5, 19.5)
          c.closePath()
          c.stroke()
          c.beginPath()
          c.arc(21, 6, 1.25, 0, Math.PI * 2)
          c.fill()
          c.beginPath()
          c.arc(21, 11, 1.05, 0, Math.PI * 2)
          c.fill()
        }
      }
    }
    tooltipText: root.hasActivity ? ("Breadcrumb · " + root.activity.name) : "Breadcrumb"
    active: root.loadState === "error"
    activeColor: root.urgent
    onPressed: function(b) {
      if (b === Qt.MiddleButton) refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    objectName: "breadcrumbPanel"
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.contentWidthHint > 0 ? root.contentWidthHint : Style.space(root.expanded ? 720 : 380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      objectName: "keyCatcher"
      anchors.fill: parent
      focus: true
      blocked: root.catcherBlocked
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { root.moveKeyboardCursor(dx, dy) }
      onActivateRequested: {
        root.catcherActivateCount += 1
        root.activateKeyboardCursor()
      }

      Item {
        id: catcherFocus
        objectName: "catcherFocus"
        width: 1
        height: 1
        focus: true
        activeFocusOnTab: true
      }

      Flickable {
        id: panelScroller
        objectName: "panelScroller"
        anchors.fill: parent
        clip: true
        focus: false
        activeFocusOnTab: false
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: column.implicitHeight
        interactive: contentHeight > height
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: column
          width: panelScroller.width
          spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(8)
          Text {
            text: "Breadcrumb"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            textFormat: Text.PlainText
          }
          Button {
            id: expandButton
            objectName: "expandButton"
            text: root.expanded ? "Collapse" : "Expand"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            focusable: (!root.busy)
            opacity: (!root.busy) ? 1 : 0.45
            onClicked: { if (!root.busy) root.toggleView() }
          }
        }

        Column {
          width: parent.width
          visible: root.conflictPrompt
          spacing: Style.space(6)
          Text {
            width: parent.width
            text: "Stale-report: A newer checkpoint was saved after this draft. Your draft is still here. Compact still shows the published checkpoint."
            color: root.fg
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
          Text {
            width: parent.width
            visible: root.hasCurrent
            text: "Published: " + (root.current ? (root.current.summary || "") : "")
            color: root.fg
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }
          Row {
            spacing: Style.space(6)
            Button {
              text: "Save draft as checkpoint"
              focusable: (!root.busy)
              opacity: (!root.busy) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy) root.resolveConflictSave() }
            }
            Button {
              text: "Load published"
              focusable: (!root.busy)
              opacity: (!root.busy) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy) root.resolveConflictLoadPublished() }
            }
            Button {
              text: "Keep editing"
              focusable: (!root.busy)
              opacity: (!root.busy) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy) root.resolveConflictKeepEditing() }
            }
          }
        }

        Column {
          width: parent.width
          visible: !!root.deleteConfirm
          spacing: Style.space(6)
          Text {
            width: parent.width
            text: "Permanently delete \"" + (root.deleteConfirm ? root.deleteConfirm.expected_name : "") + "\"? This removes all checkpoints, history, links, and the draft. This cannot be undone."
            color: root.fg
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
          Row {
            spacing: Style.space(6)
            Button {
              text: "Delete permanently"
              focusable: (!root.busy)
              opacity: (!root.busy) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy) root.confirmDeleteArchived() }
            }
            Button {
              text: "Cancel"
              focusable: (!root.busy)
              opacity: (!root.busy) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy) root.cancelDeleteArchived() }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.loadState === "loading"
          text: "Loading checkpoint…"
          color: root.fg
          opacity: 0.75
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }

        Text {
          objectName: "errorText"
          width: parent.width
          visible: root.lastError !== ""
          text: root.lastError
          color: root.urgent
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }
        Text {
          width: parent.width
          visible: root.navBlockedReason !== ""
          text: root.navBlockedReason
          color: root.fg
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }
        Button {
          visible: root.lastError !== ""
          text: "Reload"
          focusable: (!root.busy)
          opacity: (!root.busy) ? 1 : 0.45
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          bordered: true
          onClicked: { if (!root.busy) root.refresh() }
        }

        Column {
          width: parent.width
          visible: !root.hasActivity && root.loadState !== "loading"
          spacing: Style.space(8)

          Text {
            width: parent.width
            text: "Create a named activity to save your first checkpoint."
            color: root.fg
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
          TextField {
            id: emptyNameField
            width: parent.width
            text: root.editName
            foreground: root.fg
            onTextChanged: root.editName = text
            onActiveFocusChanged: root.noteEditorFocus(activeFocus)
          }
          Button {
            text: root.busy ? "Creating…" : "Create activity"
            focusable: (!root.busy && root.editName.trim().length > 0)
            opacity: (!root.busy && root.editName.trim().length > 0) ? 1 : 0.45
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            onClicked: { if (!root.busy && root.editName.trim().length > 0) root.createActivity() }
          }
        }

        Column {
          id: compactColumn
          objectName: "compactColumn"
          width: parent.width
          spacing: Style.space(8)
          visible: root.hasActivity && !root.expanded

          Dropdown {
            id: activityPicker
            width: parent.width
            label: "Activity"
            value: root.activity ? root.activity.id : ""
            options: {
              var acts = root.activities
              var current = root.activity
              return root.buildActivityOptions()
            }
            foreground: root.fg
            fontFamily: root.fontFamily
            onChanged: function(v) { root.switchActivity(v) }
            onPopupOpenChanged: root.notePopup(popupOpen)
          }
          Text {
            width: parent.width
            text: root.activity ? root.activity.name : ""
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }
          Text {
            visible: !!(root.activity && root.activity.archived_at)
            text: "Archived"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }
          Text {
            visible: root.hasCurrent
            text: Model.stateLabel(root.current ? root.current.state : "")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }
          Text {
            width: parent.width
            visible: !root.hasCurrent
            text: "No checkpoint saved yet. Expand to write one."
            color: root.fg
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
          Text {
            id: compactSummary
            objectName: "compactSummary"
            width: parent.width
            visible: root.hasCurrent
            text: root.current ? (root.current.summary || "") : ""
            color: root.fg
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
          Text {
            objectName: "draftIndicator"
            width: parent.width
            visible: root.hasDraft
            text: "Unsaved draft — expand to continue editing. Compact still shows the last published checkpoint."
            color: root.fg
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            textFormat: Text.PlainText
          }
          Column {
            width: parent.width
            visible: root.hasCurrent
            spacing: Style.space(4)
            Text {
              text: "Next step"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            Text {
              id: compactNext
              objectName: "compactNext"
              width: parent.width
              text: root.current && root.current.next_step ? root.current.next_step : "No next step"
              color: root.fg
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              textFormat: Text.PlainText
            }
          }
          Text {
            objectName: "compactMeta"
            width: parent.width
            visible: root.hasCurrent
            text: "Last saved " + Model.formatSavedAt(root.current ? root.current.saved_at : "") + " · reported by " + Model.reportedAuthor(root.current ? root.current.author : "")
            color: root.muted
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }
        }

        Grid {
          id: expandedGrid
          width: parent.width
          columns: root.narrow ? 1 : 2
          columnSpacing: Style.space(12)
          rowSpacing: Style.space(12)
          visible: root.hasActivity && root.expanded

          Column {
            id: activitySidebar
            objectName: "activitySidebar"
            width: root.narrow ? expandedGrid.width : Style.space(200)
            spacing: Style.space(6)

            Text {
              text: "Activities"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              textFormat: Text.PlainText
            }
            Text {
              width: parent.width
              visible: (root.activities || []).length === 0
              text: root.showArchived ? "No archived activities." : "No activities yet."
              color: root.muted
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            Flickable {
              id: activityScroller
              objectName: "activityScroller"
              width: parent.width
              height: Math.min(activityList.implicitHeight, Style.space(220))
              clip: true
              contentWidth: width
              contentHeight: activityList.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              Column {
                id: activityList
                width: activityScroller.width
                spacing: Style.space(4)
                Repeater {
                  model: root.activities
                  delegate: Button {
                    required property var modelData
                    width: activityList.width
                    clip: true
                    text: root.elidedLabel(root.activityLabel(modelData), 28)
                    tooltipText: root.activityLabel(modelData)
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    bordered: true
                    selected: !!(root.activity && root.activity.id === modelData.id)
                    focusable: (!root.busy)
                    opacity: (!root.busy) ? 1 : 0.45
                    onClicked: { if (!root.busy) root.switchActivity(modelData.id) }
                  }
                }
              }
            }
            TextField {
              id: createNameField
              width: parent.width
              text: root.createName
              foreground: root.fg
              onTextChanged: root.createName = text
              onActiveFocusChanged: root.noteEditorFocus(activeFocus)
            }
            Button {
              text: "Create activity"
              focusable: (!root.busy && root.createName.trim().length > 0)
              opacity: (!root.busy && root.createName.trim().length > 0) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy && root.createName.trim().length > 0) root.createActivity() }
            }
            Text {
              text: "Rename"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            TextField {
              id: renameField
              width: parent.width
              text: root.renameName
              foreground: root.fg
              onTextChanged: root.renameName = text
              onActiveFocusChanged: root.noteEditorFocus(activeFocus)
            }
            Button {
              text: "Rename activity"
              focusable: (!root.busy && root.renameName.trim().length > 0)
              opacity: (!root.busy && root.renameName.trim().length > 0) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy && root.renameName.trim().length > 0) root.renameActivity() }
            }
            Button {
              text: "Archive activity"
              focusable: (!root.busy && root.hasActivity)
              opacity: (!root.busy && root.hasActivity) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy && root.hasActivity) root.archiveActivity(root.activity.id) }
            }
            Button {
              visible: !!(root.activity && root.activity.archived_at)
              text: "Delete permanently"
              focusable: (!root.busy && !!(root.activity && root.activity.archived_at))
              opacity: (!root.busy && !!(root.activity && root.activity.archived_at)) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy && root.activity && root.activity.archived_at) root.requestDeleteArchived() }
            }
            Button {
              text: root.showArchived ? "Hide archived" : "Show archived"
              focusable: (!root.busy)
              opacity: (!root.busy) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy) root.toggleArchived() }
            }
          }

          Column {
            id: expandedEditor
            objectName: "expandedEditor"
            width: root.narrow ? expandedGrid.width : Math.max(1, expandedGrid.width - Style.space(212))
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: root.activity ? root.activity.name : ""
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }
            Text {
              text: "Stable ID " + (root.activity ? root.activity.id : "")
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
              width: parent.width
              textFormat: Text.PlainText
            }
            Dropdown {
              id: statePicker
              objectName: "statePicker"
              width: parent.width
              label: "State"
              value: root.editState
              options: Model.stateOptions()
              foreground: root.fg
              fontFamily: root.fontFamily
              onChanged: function(v) { root.editState = v; root.markUserEdit() }
              onPopupOpenChanged: root.notePopup(popupOpen)
            }
            Text {
              text: "Summary"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            TextField {
              id: summaryField
              objectName: "expandedSummary"
              width: parent.width
              text: root.editSummary
              foreground: root.fg
              onTextChanged: root.editSummary = text
              onTextEdited: root.markUserEdit()
              onActiveFocusChanged: {
                root.noteEditorFocus(activeFocus)
                if (activeFocus)
                  root.revealItem(summaryField)
              }
            }
            Text {
              text: root.editState === "done" ? "Next step (optional)" : "Next step"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            TextField {
              id: nextField
              objectName: "expandedNext"
              width: parent.width
              text: root.editNext
              foreground: root.fg
              onTextChanged: root.editNext = text
              onTextEdited: root.markUserEdit()
              onActiveFocusChanged: {
                root.noteEditorFocus(activeFocus)
                if (activeFocus)
                  root.revealItem(nextField)
              }
            }
            Text {
              text: "Context"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            TextArea {
              id: contextArea
              objectName: "contextArea"
              width: parent.width
              height: Style.space(90)
              text: root.editContext
              wrapMode: TextEdit.Wrap
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              selectedTextColor: root.fg
              selectionColor: Color.accent
              placeholderText: "Optional longer notes"
              placeholderTextColor: root.muted
              leftPadding: Style.space(8)
              rightPadding: Style.space(8)
              topPadding: Style.space(6)
              bottomPadding: Style.space(6)
              background: Rectangle {
                color: Color.background
                border.width: 1
                border.color: contextArea.activeFocus ? Color.accent : root.muted
                radius: Style.cornerRadius
              }
              onTextChanged: root.editContext = text
              onTextEdited: root.markUserEdit()
              onActiveFocusChanged: {
                root.noteEditorFocus(activeFocus)
                if (activeFocus)
                  root.revealItem(contextArea)
              }
            }
            Text {
              text: "Reported author"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            Text {
              width: parent.width
              text: "Attribution for this report, not a verified identity."
              color: root.muted
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            TextField {
              id: authorField
              width: parent.width
              text: root.editAuthor
              foreground: root.fg
              onTextChanged: root.editAuthor = text
              onTextEdited: root.markUserEdit()
              onActiveFocusChanged: root.noteEditorFocus(activeFocus)
            }
            Text {
              text: "Links"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            Repeater {
              model: linkModel
              delegate: Column {
                required property int index
                required property string label
                required property string kind
                required property string target
                width: parent.width
                spacing: Style.space(4)
                TextField {
                  width: parent.width
                  text: label
                  foreground: root.fg
                  onTextChanged: linkModel.setProperty(index, "label", text)
                  onTextEdited: root.markUserEdit()
                  onActiveFocusChanged: root.noteEditorFocus(activeFocus)
                }
                Row {
                  spacing: Style.space(6)
                  Dropdown {
                    width: Style.space(120)
                    value: kind
                    options: Model.kindOptions()
                    showLabel: false
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    onChanged: function(v) { linkModel.setProperty(index, "kind", v); root.markUserEdit() }
                    onPopupOpenChanged: root.notePopup(popupOpen)
                  }
                  TextField {
                    width: Style.space(180)
                    text: target
                    foreground: root.fg
                    onTextChanged: linkModel.setProperty(index, "target", text)
                    onTextEdited: root.markUserEdit()
                    onActiveFocusChanged: root.noteEditorFocus(activeFocus)
                  }
                }
                Row {
                  spacing: Style.space(6)
                  Button {
                    id: openLinkButton
                    objectName: "openLinkButton"
                    text: "Open"
                    focusable: (!root.busy && target.length > 0)
                    opacity: (!root.busy && target.length > 0) ? 1 : 0.45
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    bordered: true
                    onActiveFocusChanged: { if (activeFocus) root.revealItem(openLinkButton) }
                    onClicked: { if (!root.busy && target.length > 0) root.openValidatedLink(kind, target) }
                  }
                  Button {
                    text: "Remove"
                    focusable: (!root.busy)
                    opacity: (!root.busy) ? 1 : 0.45
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    bordered: true
                    onClicked: { if (!root.busy) { linkModel.remove(index); root.markUserEdit() } }
                  }
                }
              }
            }
            Button {
              id: addLinkButton
              objectName: "addLinkButton"
              text: "Add link"
              focusable: (!root.busy && linkModel.count < 20)
              opacity: (!root.busy && linkModel.count < 20) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onActiveFocusChanged: { if (activeFocus) root.revealItem(addLinkButton) }
              onClicked: { if (!root.busy && linkModel.count < 20) { linkModel.append({ label: "", kind: "web", target: "" }); root.markUserEdit() } }
            }
            Text {
              width: parent.width
              visible: root.draftStatus !== ""
              text: root.draftStatus === "saving" ? "Saving draft…" : (root.draftStatus === "saved" ? "Draft saved" : "")
              color: root.fg
              opacity: 0.75
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            Button {
              id: saveCheckpointButton
              objectName: "saveCheckpointButton"
              text: root.busy ? "Saving…" : "Save checkpoint"
              focusable: (!root.busy)
              opacity: (!root.busy) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              onActiveFocusChanged: { if (activeFocus) root.revealItem(saveCheckpointButton) }
              onClicked: { if (!root.busy) root.saveCheckpoint() }
            }
            Button {
              text: "Discard draft"
              visible: root.hasDraft
              focusable: (!root.busy)
              opacity: (!root.busy) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy) root.discardDraft() }
            }
            Text {
              width: parent.width
              visible: root.hasCurrent
              text: "Last saved " + Model.formatSavedAt(root.current ? root.current.saved_at : "") + " · revision " + root.revision
              color: root.muted
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }

            Text {
              text: "History"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
              textFormat: Text.PlainText
            }
            Text {
              width: parent.width
              visible: (root.historyEntries || []).length === 0
              text: "No history yet."
              color: root.fg
              opacity: 0.7
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            Repeater {
              model: root.historyEntries
              delegate: Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(2)
                Text {
                  objectName: "historyDate"
                  width: parent.width
                  text: Model.formatSavedAt(modelData.saved_at) + " · revision " + modelData.revision
                  color: root.fg
                  opacity: 0.7
                  wrapMode: Text.WordWrap
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  textFormat: Text.PlainText
                }
                Text {
                  width: parent.width
                  text: modelData.summary || ""
                  color: root.fg
                  wrapMode: Text.WordWrap
                  elide: Text.ElideRight
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  textFormat: Text.PlainText
                }
                Button {
                  id: restoreCheckpointButton
                  objectName: "restoreCheckpointButton"
                  text: "Restore"
                  focusable: (!root.busy && !!modelData.id)
                  opacity: (!root.busy && !!modelData.id) ? 1 : 0.45
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  bordered: true
                  onActiveFocusChanged: { if (activeFocus) root.revealItem(restoreCheckpointButton) }
                  onClicked: { if (!root.busy && !!modelData.id) root.restoreCheckpoint(modelData.id) }
                }
              }
            }
            Button {
              visible: root.historyHasMore
              text: "Older"
              focusable: (!root.busy)
              opacity: (!root.busy) ? 1 : 0.45
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { if (!root.busy) root.loadMoreHistory() }
            }
          }
        }

        Text {
          width: parent.width
          text: "Local checkpoints · last saved report, not live status. Reported author is attribution, not authentication."
          color: root.muted
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }
      }
      }
    }
  }

  Timer {
    id: openTimeout
    interval: 8000
    repeat: false
    onTriggered: {
      if (openProc.running)
        openProc.running = false
      if (root.openLaunchState === "starting" || root.openLaunchState === "started")
        root.noteOpenLaunchFailure()
    }
  }

  Process {
    id: openProc
    onStarted: {
      root.openLaunchStarted = true
      root.openLaunchState = "started"
    }
    onExited: function(exitCode, exitStatus) {
      root.openLaunchExitCode = exitCode
      openTimeout.stop()
      if (root.openLaunchState === "failed")
        return
      if (!root.openLaunchStarted || exitCode !== 0)
        root.noteOpenLaunchFailure()
      else {
        root.openLaunchState = "exited"
        root.lastError = ""
      }
    }
  }

  Process {
    id: probeProc
    stdout: StdioCollector {
      id: probeOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.handleProbe(probeOut.text)
    }
  }

  Process {
    id: storeProc
    stdout: StdioCollector {
      id: storeOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: storeErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.handleStoreResult(exitCode, storeOut.text)
      root.pendingAction = ""
      root.pendingOpen = null
      root.inFlight = null
      root.pumpQueue()
    }
  }
}
