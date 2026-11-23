import QtQuick
import qs.Commons
import qs.Commons as Commons

// Graphique d'historique en points, façon Boxtop : une colonne de points par relevé,
// le plus récent à droite. Deux séries possibles (ex. réseau entrant / sortant).
Canvas {
  id: g
  property var values: []
  property var values2: []
  property real maxValue: 0          // 0 = échelle automatique
  property color tint: Commons.Color.accent
  property color tint2: Commons.Color.urgent
  property int step: 4
  property var marks: []   // [{ i: index dans values, color }]
  readonly property int cols: Math.floor(width / step)
  readonly property color faint: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.08)
  readonly property real scaleMax: {
    if (maxValue > 0) return maxValue
    var m = 0
    for (var i = 0; i < values.length; i++) m = Math.max(m, values[i])
    for (var j = 0; j < values2.length; j++) m = Math.max(m, values2[j])
    return Math.max(m, 1e-9)
  }

  onValuesChanged: requestPaint()
  onMarksChanged: requestPaint()
  onValues2Changed: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var cols = Math.floor(width / step), rows = Math.floor(height / step)
    if (cols <= 0 || rows <= 0) return
    ctx.fillStyle = faint
    for (var c = 0; c < cols; c++)
      for (var r = 0; r < rows; r++)
        ctx.fillRect(c * step, height - (r + 1) * step + 1, 2, 2)
    function series(vals, color) {
      ctx.fillStyle = color
      for (var c = 0; c < cols; c++) {
        var i = vals.length - cols + c
        if (i < 0) continue
        var n = Math.round(rows * Math.max(0, Math.min(1, vals[i] / g.scaleMax)))
        if (vals[i] > 0 && n === 0) n = 1
        for (var r = 0; r < n; r++) ctx.fillRect(c * g.step, g.height - (r + 1) * g.step + 1, 2, 2)
      }
    }
    series(values, tint)
    if (values2.length) { ctx.globalAlpha = 0.85; series(values2, tint2); ctx.globalAlpha = 1 }
    // repères d'événements : une ligne de points verticale dans la couleur de l'événement
    for (var mi = 0; mi < g.marks.length; mi++) {
      var mc = g.marks[mi].i - (g.values.length - cols)
      if (mc < 0 || mc >= cols) continue
      ctx.fillStyle = g.marks[mi].color
      for (var mr = 0; mr < rows; mr += 2) ctx.fillRect(mc * g.step, g.height - (mr + 1) * g.step + 1, 2, 2)
      if (g.marks[mi].glyph) {
        ctx.font = "bold 9px monospace"
        ctx.fillText(g.marks[mi].glyph, mc * g.step - 3, 9)
      } else ctx.fillRect(mc * g.step - 1, 0, 4, 3)
    }
  }
}
