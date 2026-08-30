import QtQuick
import qs.Commons

// Samsung's black Buds4 Pro product artwork, cut out onto transparency with a
// fine shell-coloured keyline. Keep the pair together even at bar size: this
// plugin represents the device, not an individual left or right bud.
Item {
  id: root

  property real iconSize: 16
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize

  Image {
    anchors.fill: parent
    source: "assets/buds4-pro-black-flat.png"
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    asynchronous: false
    cache: true
  }
}
