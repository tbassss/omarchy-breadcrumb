import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Named activities + dated history + crash-safe per-activity drafts (#5).
// Compact shows the published checkpoint and a draft indicator. Expanded
// edits the draft. Persistence is the Python store CLI via Process argv,
// not a public agent API. Stale Save never overwrites; resolution is explicit.
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

  readonly property bool busy: storeProc.running
  readonly property bool expanded: root.view === "expanded"
  readonly property bool hasActivity: !!(root.activity && root.activity.id)
  readonly property bool hasCurrent: !!(root.current && root.current.id)
  readonly property string storePath: Model.fileFromUrl(Qt.resolvedUrl("bin/breadcrumb-store"))
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

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
    if (activityChanged || (!root.pendingAutosave && !root.dirty))
      hydrateEditorFromSnapshot(body)
    root.syncActivityPicker()
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
    runStore("archive-activity", { activity_id: target })
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
    runStore("validate-link", { kind: kind, target: target })
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
      Quickshell.execDetached(body.open_argv)
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

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰆓"
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
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.expanded ? 720 : 380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
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
            text: root.expanded ? "Collapse" : "Expand"
            foreground: root.fg
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            enabled: !root.busy
            onClicked: root.toggleView()
          }
        }

        Column {
          width: parent.width
          visible: root.conflictPrompt
          spacing: Style.space(6)
          Text {
            width: parent.width
            text: "A newer checkpoint was saved. Your draft is still here."
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
              enabled: !root.busy
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.resolveConflictSave()
            }
            Button {
              text: "Load published"
              enabled: !root.busy
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.resolveConflictLoadPublished()
            }
            Button {
              text: "Keep editing"
              enabled: !root.busy
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.resolveConflictKeepEditing()
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
          enabled: !root.busy
          foreground: root.fg
          fontFamily: root.fontFamily
          fontSize: Style.font.bodySmall
          bordered: true
          onClicked: root.refresh()
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
            width: parent.width
            text: root.editName
            foreground: root.fg
            onTextChanged: root.editName = text
          }
          Button {
            text: root.busy ? "Creating…" : "Create activity"
            enabled: !root.busy && root.editName.trim().length > 0
            foreground: root.fg
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.createActivity()
          }
        }

        Column {
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
            color: root.fg
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }
          Text {
            visible: root.hasCurrent
            text: Model.stateLabel(root.current ? root.current.state : "")
            color: root.fg
            opacity: 0.8
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
            width: parent.width
            visible: root.hasCurrent
            text: root.current ? (root.current.summary || "") : ""
            color: root.fg
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
          Text {
            width: parent.width
            visible: root.hasDraft
            text: "Unsaved draft"
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
              color: root.fg
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            Text {
              width: parent.width
              text: root.current && root.current.next_step ? root.current.next_step : "No next step"
              color: root.fg
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              textFormat: Text.PlainText
            }
          }
          Text {
            width: parent.width
            visible: root.hasCurrent
            text: (root.current ? root.current.saved_at : "") + " · " + (root.current ? root.current.author : "")
            color: root.fg
            opacity: 0.7
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            textFormat: Text.PlainText
          }
        }

        Row {
          width: parent.width
          spacing: Style.space(12)
          visible: root.hasActivity && root.expanded

          Column {
            id: activitySidebar
            width: Style.space(200)
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
              color: root.fg
              opacity: 0.7
              wrapMode: Text.WordWrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            Repeater {
              model: root.activities
              delegate: Button {
                required property var modelData
                width: activitySidebar.width
                text: root.activityLabel(modelData)
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                bordered: true
                enabled: !root.busy
                onClicked: root.switchActivity(modelData.id)
              }
            }
            TextField {
              width: parent.width
              text: root.createName
              foreground: root.fg
              onTextChanged: root.createName = text
            }
            Button {
              text: "Create activity"
              enabled: !root.busy && root.createName.trim().length > 0
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.createActivity()
            }
            Text {
              text: "Rename"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            TextField {
              width: parent.width
              text: root.renameName
              foreground: root.fg
              onTextChanged: root.renameName = text
            }
            Button {
              text: "Rename activity"
              enabled: !root.busy && root.renameName.trim().length > 0
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.renameActivity()
            }
            Button {
              text: "Archive activity"
              enabled: !root.busy && root.hasActivity
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.archiveActivity(root.activity.id)
            }
            Button {
              text: root.showArchived ? "Hide archived" : "Show archived"
              enabled: !root.busy
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.toggleArchived()
            }
          }

          Column {
            width: column.width - Style.space(212)
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
              color: root.fg
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
              width: parent.width
              textFormat: Text.PlainText
            }
            Dropdown {
              width: parent.width
              label: "State"
              value: root.editState
              options: Model.stateOptions()
              foreground: root.fg
              fontFamily: root.fontFamily
              onChanged: function(v) { root.editState = v; root.markUserEdit() }
            }
            Text {
              text: "Summary"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            TextField {
              width: parent.width
              text: root.editSummary
              foreground: root.fg
              onTextChanged: root.editSummary = text
              onTextEdited: root.markUserEdit()
            }
            Text {
              text: root.editState === "done" ? "Next step (optional)" : "Next step"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            TextField {
              width: parent.width
              text: root.editNext
              foreground: root.fg
              onTextChanged: root.editNext = text
              onTextEdited: root.markUserEdit()
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
              width: parent.width
              height: Style.space(90)
              text: root.editContext
              wrapMode: TextEdit.Wrap
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              placeholderText: "Optional longer notes"
              onTextChanged: root.editContext = text
              onTextEdited: root.markUserEdit()
            }
            Text {
              text: "Reported author"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
            }
            TextField {
              width: parent.width
              text: root.editAuthor
              foreground: root.fg
              onTextChanged: root.editAuthor = text
              onTextEdited: root.markUserEdit()
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
                  }
                  TextField {
                    width: Style.space(180)
                    text: target
                    foreground: root.fg
                    onTextChanged: linkModel.setProperty(index, "target", text)
                    onTextEdited: root.markUserEdit()
                  }
                }
                Row {
                  spacing: Style.space(6)
                  Button {
                    text: "Open"
                    enabled: !root.busy && target.length > 0
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    bordered: true
                    onClicked: root.openValidatedLink(kind, target)
                  }
                  Button {
                    text: "Remove"
                    enabled: !root.busy
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    fontSize: Style.font.bodySmall
                    bordered: true
                    onClicked: { linkModel.remove(index); root.markUserEdit() }
                  }
                }
              }
            }
            Button {
              text: "Add link"
              enabled: !root.busy && linkModel.count < 20
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: { linkModel.append({ label: "", kind: "web", target: "" }); root.markUserEdit() }
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
              text: root.busy ? "Saving…" : "Save checkpoint"
              enabled: !root.busy
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.saveCheckpoint()
            }
            Button {
              text: "Discard draft"
              visible: root.hasDraft
              enabled: !root.busy
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.discardDraft()
            }
            Text {
              width: parent.width
              visible: root.hasCurrent
              text: "Last saved " + (root.current ? root.current.saved_at : "") + " · revision " + root.revision
              color: root.fg
              opacity: 0.7
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
                  width: parent.width
                  text: (modelData.saved_at || "") + " · revision " + modelData.revision
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
                  text: "Restore"
                  enabled: !root.busy && !!modelData.id
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  bordered: true
                  onClicked: root.restoreCheckpoint(modelData.id)
                }
              }
            }
            Button {
              visible: root.historyHasMore
              text: "Older"
              enabled: !root.busy
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.loadMoreHistory()
            }
          }
        }

        Text {
          width: parent.width
          text: "Local checkpoints · last saved report, not live status"
          color: root.fg
          opacity: 0.55
          wrapMode: Text.WordWrap
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          textFormat: Text.PlainText
        }
      }
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
