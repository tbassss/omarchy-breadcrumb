import QtQuick

// Minimal facade of /usr/share/omarchy/shell/Ui/PanelKeyCatcher.qml
Item {
  id: root
  property bool blocked: false
  signal moveRequested(int dx, int dy)
  signal activateRequested()
  signal returnRequested()
  signal closeRequested()
  signal deleteRequested()
  signal tabRequested(int direction)
  signal textKey(string text)
}
