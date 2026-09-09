import QtQuick

// Minimal facade of /usr/share/omarchy/shell/Ui/Button.qml
Item {
  id: root
  property string text: ""
  property color foreground: "#cacccc"
  property string fontFamily: "sans-serif"
  property real fontSize: 12
  property bool bordered: false
  property bool enabled: true
  signal clicked()
  implicitWidth: 80
  implicitHeight: 24
}
