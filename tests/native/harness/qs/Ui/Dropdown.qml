import QtQuick

// Facade aligned with installed /usr/share/omarchy/shell/Ui/Dropdown.qml.
// Real ListView.selectCurrent() takes no argument: it assigns root.value
// from currentIndex THEN emits changed(v). Isolated Cave overlays the
// packaged file. Tests must not call selectCurrent(value).
Item {
  id: root
  property string label: ""
  property string value: ""
  property var options: []
  property color foreground: "#cacccc"
  property string fontFamily: "sans-serif"
  property bool showLabel: true
  property bool popupOpen: false
  signal changed(string value)
  implicitWidth: 160
  implicitHeight: 32

  function optionValue(opt) {
    if (opt && opt.value !== undefined)
      return String(opt.value)
    return String(opt)
  }

  function selectCurrent() {
    var selected = String(root.value)
    root.value = selected
    root.changed(selected)
  }

  function open() { root.popupOpen = true }
  function close() { root.popupOpen = false }
  function toggle() { root.popupOpen = !root.popupOpen }
}
