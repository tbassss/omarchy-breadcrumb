import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Named activities + dated history (#4). Compact picker and Expanded sidebar
// share one store snapshot. Persistence is the Python store CLI via Process
// argv, not a public agent API. Switching never silently discards an in-memory
// edit: Save / Discard / Cancel.
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
  property bool dirty: false // genuine user edits (onTextEdited); construction onTextChanged is not a draft
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
  property bool switchPrompt: false
  property string pendingSwitchId: ""

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

  function applySnapshot(body) {
    var previousId = root.activity && root.activity.id ? root.activity.id : ""
    root.activity = body.activity || null
    root.current = body.current || null
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
    var newId = root.activity && root.activity.id ? root.activity.id : ""
    if (newId && newId !== previousId)
      root.dirty = false
    if (!root.dirty) {
      copyCurrentToEditor()
      Qt.callLater(function() { root.dirty = false })
    }
    if (root.hasActivity) {
      root.editName = root.activity.name || ""
      root.renameName = root.activity.name || ""
    }
    root.syncActivityPicker()
  }

  function syncActivityPicker() {
    if (!activityPicker)
      return
    var id = root.activity && root.activity.id ? String(root.activity.id) : ""
    activityPicker.value = id
  }

  function copyCurrentToEditor() {
    if (!root.hasCurrent) {
      root.editSummary = ""
      root.editNext = ""
      root.editContext = ""
      root.editState = "ready"
      root.editAuthor = Model.defaultAuthor()
      linkModel.clear()
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

  function runStore(action, payload) {
    if (storeProc.running)
      return
    root.pendingAction = action
    if (root.loadState !== "error")
      root.loadState = root.loadState === "ready" || root.loadState === "empty" ? root.loadState : "loading"
    if (action === "get" && !root.hasCurrent && !root.hasActivity)
      root.loadState = "loading"
    storeProc.command = ["/usr/bin/python3", root.storePath, action, JSON.stringify(payload || {})]
    storeProc.running = true
  }

  function refresh() {
    var payload = { include_archived: root.showArchived }
    if (root.activity && root.activity.id)
      payload.activity_id = root.activity.id
    runStore("get", payload)
  }

  function createActivity() {
    if (root.dirty) {
      root.lastError = "Save or discard the current edit before creating another activity."
      root.syncActivityPicker()
      return
    }
    var name = String(root.createName || "").trim()
    if (!name)
      name = String(root.editName || "").trim()
    runStore("create-activity", { name: name })
  }

  function saveCheckpoint() {
    if (!root.hasActivity)
      return
    runStore("publish", {
      activity_id: root.activity.id,
      expected_revision: root.revision,
      summary: root.editSummary,
      next_step: root.editNext,
      context: root.editContext,
      state: root.editState,
      author: root.editAuthor || Model.defaultAuthor(),
      links: collectLinks()
    })
  }

  function switchActivity(id) {
    if (!id)
      return
    if (root.activity && id === root.activity.id) {
      root.switchPrompt = false
      root.pendingSwitchId = ""
      root.syncActivityPicker()
      return
    }
    if (root.dirty) {
      root.pendingSwitchId = id
      root.switchPrompt = true
      root.syncActivityPicker()
      return
    }
    doSwitch(id)
  }

  function doSwitch(id) {
    root.switchPrompt = false
    root.pendingSwitchId = ""
    runStore("get", { activity_id: id, include_archived: root.showArchived })
  }

  function confirmSwitchSave() {
    if (!root.pendingSwitchId)
      return
    saveCheckpoint()
  }

  function confirmSwitchDiscard() {
    var id = root.pendingSwitchId
    root.dirty = false
    copyCurrentToEditor()
    doSwitch(id)
  }

  function cancelSwitch() {
    root.pendingSwitchId = ""
    root.switchPrompt = false
    root.syncActivityPicker()
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
    if (root.dirty) {
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

  function handleStoreResult(exitCode, raw) {
    var body = Model.parseResponse(raw)
    if (!body.ok) {
      root.lastError = body.message || "Could not complete that action."
      if (root.pendingAction !== "set-view")
        root.loadState = root.hasCurrent || root.hasActivity ? root.loadState : "error"
      if (root.loadState === "loading")
        root.loadState = "error"
      root.syncActivityPicker()
      return
    }
    root.lastError = ""
    var action = root.pendingAction
    if (action === "create-activity") {
      root.dirty = false
      root.createName = ""
      applySnapshot({
        activity: body.activity || null,
        current: null,
        revision: 0,
        state: "empty",
        view: root.view
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
      root.dirty = false
      applySnapshot({
        activity: root.activity,
        current: body.current || null,
        revision: body.revision,
        view: root.view,
        state: body.state
      })
      if (action === "publish" && root.pendingSwitchId) {
        var switchId = root.pendingSwitchId
        root.pendingSwitchId = ""
        root.switchPrompt = false
        Qt.callLater(function() { root.doSwitch(switchId) })
        return
      }
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
          visible: root.switchPrompt
          spacing: Style.space(6)
          Text {
            width: parent.width
            text: "Save or discard this edit before switching activities."
            color: root.fg
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            textFormat: Text.PlainText
          }
          Row {
            spacing: Style.space(6)
            Button {
              text: "Save"
              enabled: !root.busy
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.confirmSwitchSave()
            }
            Button {
              text: "Discard"
              enabled: !root.busy
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.confirmSwitchDiscard()
            }
            Button {
              text: "Cancel"
              enabled: !root.busy
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              onClicked: root.cancelSwitch()
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
          spacing: Style.space(8)
          visible: !root.hasActivity && root.loadState !== "loading"

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
              onChanged: function(v) { root.editState = v; root.dirty = true }
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
              onTextEdited: root.dirty = true
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
              onTextEdited: root.dirty = true
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
              onTextEdited: root.dirty = true
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
              onTextEdited: root.dirty = true
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
                  onTextEdited: root.dirty = true
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
                    onChanged: function(v) { linkModel.setProperty(index, "kind", v); root.dirty = true }
                  }
                  TextField {
                    width: Style.space(180)
                    text: target
                    foreground: root.fg
                    onTextChanged: linkModel.setProperty(index, "target", text)
                    onTextEdited: root.dirty = true
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
                    onClicked: { linkModel.remove(index); root.dirty = true }
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
              onClicked: { linkModel.append({ label: "", kind: "web", target: "" }); root.dirty = true }
            }
            Button {
              text: root.busy ? "Saving…" : "Save checkpoint"
              enabled: !root.busy
              foreground: root.fg
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.saveCheckpoint()
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
    }
  }
}
