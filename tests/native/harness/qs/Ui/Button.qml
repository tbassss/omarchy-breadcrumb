import QtQuick

// Facade aligned with installed /usr/share/omarchy/shell/Ui/Button.qml.
// Real Button has no `enabled` property. Isolated Cave runs overlay the
// packaged file; this copy must not invent a more permissive API.
Item {
  id: root
  property string text: ""
  property color foreground: "#cacccc"
  property string fontFamily: "sans-serif"
  property real fontSize: 12
  property bool bordered: false
  property bool fillWidth: false
  property bool hasCursor: false
  property bool selected: false
  property bool active: false
  property bool focusable: false
  property string tooltipText: ""
  signal clicked()
  implicitWidth: 80
  implicitHeight: 24
  Keys.onPressed: function(event) {
    if (!root.focusable)
      return
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
      event.accepted = true
      root.clicked()
    }
  }
}
