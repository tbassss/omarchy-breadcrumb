import QtQuick

// Minimal facade of /usr/share/omarchy/shell/Ui/Dropdown.qml
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
}
