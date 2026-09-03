import QtQuick
import QtQuick.Shapes
import qs.Commons
import "BudsOutline.js" as Outline

// The Galaxy Buds4 Pro pair as a hairline outline. The path is traced from
// Samsung's product cut-out (tools/trace-icon.py) and scaled here at run
// time, so it is a single-colour mark like every other glyph in the bar:
// the stroke takes the shell foreground and follows each theme with it.
Item {
  id: root

  // Width of the pair. Height follows the product's proportions.
  property real iconSize: 16
  property color color: Color.foreground
  property real strokeWidth: 1
  // Optional wash inside the outline; 0 leaves it as pure line work.
  property real fillOpacity: 0

  implicitWidth: iconSize
  implicitHeight: Math.ceil(iconSize * Outline.ASPECT)

  // Draw inside the stroke so nothing is clipped at the edges.
  readonly property real drawWidth: Math.max(1, iconSize - strokeWidth)
  readonly property real inset: strokeWidth / 2
  readonly property color wash: Qt.rgba(color.r, color.g, color.b, color.a * fillOpacity)

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: root.wash
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathSvg { path: Outline.svgPath(0, root.drawWidth, root.inset, root.inset) }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.strokeWidth
      fillColor: root.wash
      joinStyle: ShapePath.RoundJoin
      capStyle: ShapePath.RoundCap
      PathSvg { path: Outline.svgPath(1, root.drawWidth, root.inset, root.inset) }
    }
  }
}
