pragma Singleton
import QtQuick

// Minimal facade of /usr/share/omarchy/shell/Commons/Color.qml
// Only properties required by candidate Panel.qml (issue #3).
QtObject {
  property color foreground: "#cacccc"
  property color urgent: "#a55555"
}
