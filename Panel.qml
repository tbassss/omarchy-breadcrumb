import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// First manual checkpoint slice (#3). Compact glance + Expanded editor.
// Persistence is the Python store CLI via Process argv, not a public agent API.
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
  property bool dirty: false
  property string editName: ""
  property string editSummary: ""
  property string editNext: ""
  property string editContext: ""
  property string editState: "ready"
  property string editAuthor: "You"

  readonly property bool busy: storeProc.running
  readonly property bool expanded: root.view === "expanded"
  readonly property bool hasActivity: !!(root.activity && root.activity.id)
  readonly property bool hasCurrent: !!(root.current && root.current.id)
  readonly property string storePath: Model.fileFromUrl(Qt.resolvedUrl("bin/breadcrumb-store"))
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function applySnapshot(body) {
    root.activity = body.activity || null
    root.current = body.current || null
    root.revision = body.revision || 0
    if (body.view === "compact" || body.view === "expanded")
      root.view = body.view
    if (body.state === "empty" && !root.hasActivity)
      root.loadState = "empty"
    else if (body.state === "empty")
      root.loadState = "empty"
    else
      root.loadState = "ready"
    if (!root.dirty) {
      copyCurrentToEditor()
      Qt.callLater(function() { root.dirty = false })
    }
    if (root.hasActivity)
      root.editName = root.activity.name || ""
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

  function refresh() { runStore("get", {}) }

  function createActivity() {
    runStore("ensure-activity", { name: root.editName })
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
      return
    }
    root.lastError = ""
    if (root.pendingAction === "get" || root.pendingAction === "ensure-activity" || root.pendingAction === "publish") {
      if (root.pendingAction === "ensure-activity")
        root.dirty = false
      if (root.pendingAction === "publish")
        root.dirty = false
      applySnapshot(body.activity ? body : {
        activity: root.activity,
        current: body.current || null,
        revision: body.revision,
        view: root.view,
        state: body.state
      })
      if (root.pendingAction === "ensure-activity")
        Qt.callLater(root.refresh)
      return
    }
    if (root.pendingAction === "set-view") {
      if (body.view === "compact" || body.view === "expanded")
        root.view = body.view
      return
    }
    if (root.pendingAction === "validate-link" && body.open_argv && body.open_argv.length)
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
    contentWidth: panel.fittedContentWidth(Style.space(root.expanded ? 560 : 380))
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

          Text {
            text: root.activity ? root.activity.name : ""
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
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

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.hasActivity && root.expanded

          Text {
            text: root.activity ? root.activity.name : ""
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            textFormat: Text.PlainText
          }
          Text {
            text: "Stable ID " + (root.activity ? root.activity.id : "")
            color: root.fg
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
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
            onTextChanged: { root.editSummary = text; root.dirty = true }
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
            onTextChanged: { root.editNext = text; root.dirty = true }
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
            onTextChanged: { root.editContext = text; root.dirty = true }
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
            onTextChanged: { root.editAuthor = text; root.dirty = true }
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
              width: column.width
              spacing: Style.space(4)
              TextField {
                width: parent.width
                text: label
                foreground: root.fg
                onTextChanged: { linkModel.setProperty(index, "label", text); root.dirty = true }
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
                  width: column.width - Style.space(180)
                  text: target
                  foreground: root.fg
                  onTextChanged: { linkModel.setProperty(index, "target", text); root.dirty = true }
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
