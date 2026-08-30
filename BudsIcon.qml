import QtQuick
import QtQuick.Shapes
import qs.Commons

// A pair of blade-style earbuds, drawn rather than typed: the Nerd Font's
// earbud glyphs render as fallback junk on Omarchy, and a drawn mark cannot
// depend on what the active theme's font happens to carry.
Item {
  id: root

  property real iconSize: 16
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize

  // Artboard is 40 x 32; the ink fills it, so fitting is a straight scale.
  readonly property real artW: 40
  readonly property real artH: 32
  readonly property real fit: iconSize / Math.max(artW, artH)

  Shape {
    width: root.artW
    height: root.artH
    transform: [
      Scale { xScale: root.fit; yScale: root.fit },
      Translate {
        x: (root.iconSize - root.artW * root.fit) / 2
        y: (root.iconSize - root.artH * root.fit) / 2
      }
    ]
    preferredRendererType: Shape.CurveRenderer
    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(width * root.fit * 3, height * root.fit * 3)

    // Left bud: round head at the top, blade tapering down and slightly inwards.
    ShapePath {
      fillColor: root.color
      strokeWidth: -1
      PathSvg { path: "M 10 1 C 15 1 19 4.8 19 9.5 C 19 12.6 17.3 15 14.9 16.4 L 13.6 28.5 C 13.4 30.2 12 31.4 10.3 31.4 C 8.6 31.4 7.2 30.2 7 28.5 L 5.7 16.4 C 3 15 1 12.6 1 9.5 C 1 4.8 5 1 10 1 Z" }
    }

    // Right bud, the mirror of the left.
    ShapePath {
      fillColor: root.color
      strokeWidth: -1
      PathSvg { path: "M 30 1 C 25 1 21 4.8 21 9.5 C 21 12.6 22.7 15 25.1 16.4 L 26.4 28.5 C 26.6 30.2 28 31.4 29.7 31.4 C 31.4 31.4 32.8 30.2 33 28.5 L 34.3 16.4 C 37 15 39 12.6 39 9.5 C 39 4.8 35 1 30 1 Z" }
    }
  }
}
