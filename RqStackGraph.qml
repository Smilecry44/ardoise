import QtQuick
import qs.Commons
import qs.Commons as Commons

// Historique empilé en points : chaque colonne est un relevé, découpé par catégorie
// avec les mêmes couleurs que la barre de bilan (bas = première catégorie).
Canvas {
  id: g
  property var values: []      // [[a, b, c…], …]
  property var colors: []
  property real maxValue: 1
  property int step: 4
  property var marks: []
  property real threshold: 0      // ligne du seuil d'alerte, en fraction de maxValue (0 : aucune)
  onThresholdChanged: requestPaint()
  readonly property int cols: Math.floor(width / step)
  readonly property color faint: Qt.rgba(Commons.Color.popups.text.r, Commons.Color.popups.text.g, Commons.Color.popups.text.b, 0.08)

  onValuesChanged: requestPaint()
  onMarksChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var cols = Math.floor(width / step), rows = Math.floor(height / step)
    if (cols <= 0 || rows <= 0) return
    for (var c = 0; c < cols; c++) {
      var i = values.length - cols + c
      var parts = i >= 0 ? values[i] : []
      var r = 0, acc = 0
      for (var k = 0; k < parts.length; k++) {
        acc += parts[k]
        var top = Math.round(rows * Math.min(1, acc / maxValue))
        ctx.fillStyle = colors[k] || faint
        for (; r < top; r++) ctx.fillRect(c * step, height - (r + 1) * step + 1, 2, 2)
      }
      ctx.fillStyle = faint
      for (; r < rows; r++) ctx.fillRect(c * step, height - (r + 1) * step + 1, 2, 2)
    }
    // ligne pointillée du seuil d'alerte
    if (g.threshold > 0 && g.threshold < 1) {
      var ty = Math.round(g.height - g.threshold * rows * g.step)
      ctx.fillStyle = Commons.Color.urgent
      ctx.globalAlpha = 0.7
      for (var tx = 0; tx < g.width; tx += 6) ctx.fillRect(tx, ty, 3, 1)
      ctx.globalAlpha = 1
    }
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
