import QtQuick

// Minimal facade of /usr/share/omarchy/shell/Ui/Panel.qml
// Real host also wires PanelController + IpcHandler. This component test
// keeps open/close local so we do not bind live-shell IPC sockets.
Item {
  id: root

  property QtObject bar: null
  property string moduleName: ""
  property var settings: ({})
  property string ipcTarget: ""
  property bool manageIpc: true
  property bool _open: false

  readonly property bool opened: _open
  readonly property color barForeground: bar ? bar.barForeground : "#cacccc"

  function open() { _open = true }
  function close() { _open = false }
  function toggle() { opened ? close() : open() }
  function switchPanel(direction) { return false }
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
}
