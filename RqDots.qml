import QtQuick
import qs.Commons
import qs.Commons as Commons

// Jauge en pointillés, comme btop.
Row {
  id: dotsRow
  property real frac: 0
  property color tint: Commons.Color.accent
  property int count: 14
  readonly property color faint: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.16)
  spacing: 2
  Repeater {
    model: dotsRow.count
    Rectangle {
      width: 3; height: 3; radius: 1
      color: index < Math.round(Math.max(0, Math.min(1, dotsRow.frac)) * dotsRow.count) ? dotsRow.tint : dotsRow.faint
    }
  }
}
