pragma Singleton
import QtQuick

// Minimal facade of /usr/share/omarchy/shell/Commons/Color.qml.
// Isolated Cave overlays the packaged singleton. Keep muted so Panel.qml
// theme-token use is valid even if overlay is skipped.
QtObject {
  property color foreground: "#cacccc"
  property color urgent: "#a55555"
  property color muted: "#8a8c8c"
}
