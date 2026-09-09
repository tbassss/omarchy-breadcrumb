import QtQuick
import QtQuick.Controls as Controls

// Minimal facade wrapping Qt TextField so text/onTextChanged work.
Controls.TextField {
  id: root
  property color foreground: "#cacccc"
  color: foreground
}
