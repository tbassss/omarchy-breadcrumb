import QtQuick

// Minimal facade of /usr/share/omarchy/shell/Ui/Dropdown.qml
// Installed ListView.selectCurrent assigns root.value THEN emits changed(v),
// which breaks a QML property binding on value. Native tests must mutate
// through this same assignment-before-signal path, not only Panel.switchActivity
// and not a dumb Item stub without selectCurrent.
Item {
  id: root
  property string label: ""
  property string value: ""
  property var options: []
  property color foreground: "#cacccc"
  property string fontFamily: "sans-serif"
  property bool showLabel: true
  signal changed(string value)
  implicitWidth: 160
  implicitHeight: 32

  function selectCurrent(v) {
    var selected = v !== undefined ? String(v) : String(root.value)
    root.value = selected
    root.changed(selected)
  }
}
