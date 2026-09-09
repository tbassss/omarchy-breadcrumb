import QtQuick

// Isolated stub of /usr/share/omarchy/shell/Ui/KeyboardPanel.qml.
// Real type is a WlrLayershell PanelWindow. Do not instantiate that here:
// it would attach to the compositor. Offscreen component test only.
// Children are hosted in a sized item so geometry/screenshots are real.
Item {
  id: root
  property Item anchorItem: null
  property var owner: null
  property var bar: null
  property bool open: false
  property Item focusTarget: null
  property int contentWidth: 380
  property int contentHeight: 200
  property int padding: 12
  property int margin: 5
  visible: open
  width: Math.max(1, contentWidth)
  height: Math.max(1, contentHeight)
  default property alias contentItem: contentHolder.children

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    if (cap !== undefined && Number(cap) > 0)
      desired = Math.min(desired, Number(cap))
    return Math.round(desired)
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(1, Number(implicitHeight) || 1)
    if (cap !== undefined && Number(cap) > 0)
      desired = Math.min(desired, Number(cap))
    return Math.round(desired)
  }

  function close() {
    if (owner && "close" in owner)
      owner.close()
    else
      root.open = false
  }

  Item {
    id: contentHolder
    anchors.fill: parent
  }
}
