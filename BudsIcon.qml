import QtQuick
import QtQuick.Shapes
import qs.Commons

// Galaxy Buds4 Pro, traced down to the features which survive at bar size: the
// broad offset ear body and tip, the straight blade and its circular grille.
// The grille is knocked out of the silhouette instead of drawn in a second
// colour, so the mark works on every Omarchy theme.
Item {
  id: root

  property real iconSize: 16
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real artWidth: 40
  readonly property real artHeight: 32
  readonly property real fit: iconSize / Math.max(artWidth, artHeight)

  Shape {
    width: root.artWidth
    height: root.artHeight
    scale: root.fit
    transformOrigin: Item.TopLeft
    x: (root.iconSize - root.artWidth * root.fit) / 2
    y: (root.iconSize - root.artHeight * root.fit) / 2
    preferredRendererType: Shape.CurveRenderer

    layer.enabled: true
    layer.smooth: true
    layer.textureSize: Qt.size(root.iconSize * 3, root.iconSize * 3)

    // The outer lobes are the silicone tips seen behind each housing. Compared
    // with the old icon, the blades are shorter and the bodies much wider.
    ShapePath {
      fillColor: root.color
      strokeWidth: -1
      fillRule: ShapePath.OddEvenFill
      PathSvg {
        path: "M 12.3 1.2 C 16.5 1.2 19.2 4.1 19.2 8.1 C 19.2 11.8 16.8 14.6 13.9 15.8 L 13.9 27.1 C 13.9 29.7 12.4 31.1 10.3 31.1 C 8.2 31.1 6.8 29.6 6.8 27.1 L 6.8 16.4 C 4.2 17.4 1.7 15.8 0.8 13.2 C -0.1 10.6 1.1 7.9 3.5 6.6 C 4.8 3.3 8.1 1.2 12.3 1.2 Z M 10.3 4.0 A 2.3 2.3 0 1 0 10.3 8.6 A 2.3 2.3 0 1 0 10.3 4.0 Z"
      }
    }

    ShapePath {
      fillColor: root.color
      strokeWidth: -1
      fillRule: ShapePath.OddEvenFill
      PathSvg {
        path: "M 27.7 1.2 C 23.5 1.2 20.8 4.1 20.8 8.1 C 20.8 11.8 23.2 14.6 26.1 15.8 L 26.1 27.1 C 26.1 29.7 27.6 31.1 29.7 31.1 C 31.8 31.1 33.2 29.6 33.2 27.1 L 33.2 16.4 C 35.8 17.4 38.3 15.8 39.2 13.2 C 40.1 10.6 38.9 7.9 36.5 6.6 C 35.2 3.3 31.9 1.2 27.7 1.2 Z M 29.7 4.0 A 2.3 2.3 0 1 0 29.7 8.6 A 2.3 2.3 0 1 0 29.7 4.0 Z"
      }
    }
  }
}
