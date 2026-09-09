import QtQuick

// Minimal facade of qs.Ui.BarIconButton / WidgetButton.
// Candidate uses text, tooltipText, bar, active, activeColor, onPressed.
Item {
  id: root
  property var bar: null
  property string text: ""
  property string tooltipText: ""
  property bool active: false
  property color activeColor: "#a55555"
  property color foreground: "#cacccc"
  signal pressed(int button)

  implicitWidth: 24
  implicitHeight: 24
}
