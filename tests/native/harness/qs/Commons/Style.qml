pragma Singleton
import QtQuick

// Minimal facade of /usr/share/omarchy/shell/Commons/Style.qml
// space() and font tokens used by candidate Panel.qml.
QtObject {
  id: root

  function space(px) {
    var n = Number(px)
    if (!isFinite(n) || n <= 0)
      return 0
    return Math.max(1, Math.round(n))
  }

  readonly property QtObject font: QtObject {
    readonly property string family: "sans-serif"
    readonly property int bodySmall: 11
    readonly property int body: 12
    readonly property int title: 14
  }
}
