import QtQuick
import QtQuick.Effects
import qs.Commons

// Samsung's black Buds4 Pro product artwork on transparency. MultiEffect grows
// its alpha into a fine keyline using the shell foreground passed by Panel.qml,
// so the pair follows every theme while keeping the product detail intact.
Item {
  id: root

  property real iconSize: 16
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize

  Image {
    id: product
    anchors.fill: parent
    source: "assets/buds4-pro-black-cutout.png"
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    asynchronous: false
    cache: true
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: product
    source: product
    autoPaddingEnabled: false
    shadowEnabled: true
    shadowColor: root.color
    shadowOpacity: 0.82
    shadowBlur: 0.0
    shadowScale: root.iconSize < 24 ? 1.055 : 1.022
  }
}
