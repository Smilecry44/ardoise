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
  property int notch: 0
  property int markGap: 20     // en dessous de cet écart (px), les encoches se regroupent
  onMarkGapChanged: requestPaint()      // bande du haut réservée aux encoches des événements (px)
  property int cursor: -1    // colonne (index dans values) marquée d'un trait fin, -1 : aucune
  property color cursorColor: Commons.Color.accent
  onNotchChanged: requestPaint()
  onCursorChanged: requestPaint()
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
    var cols = Math.floor(width / step), rows = Math.floor((height - notch) / step)
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
    // repères d'événements : une encoche (▲ ▼ ↗ !) au-dessus de la courbe, sans ligne dans les points.
    // Les encoches trop proches pour se lire se regroupent : on montre la plus importante
    // (alerte > fuite > fermeture > ouverture), suivie du nombre d'événements du groupe.
    var ms = []
    for (var mi = 0; mi < g.marks.length; mi++) {
      var mc = g.marks[mi].i - (g.values.length - cols)
      if (mc >= 0 && mc < cols) ms.push({ c: mc, m: g.marks[mi] })
    }
    ms.sort(function(a, b) { return a.c - b.c })
    var gapCols = Math.max(1, Math.ceil(g.markGap / g.step))
    var groups = []
    for (var k = 0; k < ms.length; k++) {
      var last = groups.length ? groups[groups.length - 1] : null
      if (last && ms[k].c - last.start <= gapCols) {
        last.n++
        if ((ms[k].m.p || 0) > (last.top.p || 0)) { last.top = ms[k].m; last.c = ms[k].c }
      } else groups.push({ start: ms[k].c, c: ms[k].c, top: ms[k].m, n: 1 })
    }
    for (var gi = 0; gi < groups.length; gi++) {
      var gr = groups[gi], x = gr.start * g.step
      ctx.fillStyle = gr.top.color
      if (g.notch > 0 && gr.top.glyph) {
        var fs = Math.max(8, g.notch - 2)
        ctx.font = "bold " + fs + "px monospace"
        ctx.fillText(gr.top.glyph, x - 3, g.notch - 2)
        if (gr.n > 1) {
          ctx.font = "bold " + Math.max(7, Math.round(fs * 0.72)) + "px monospace"
          ctx.fillText(String(gr.n), x - 3 + fs * 0.72, Math.round(g.notch * 0.55))
        }
      } else ctx.fillRect(x - 1, 0, 4, 3)
    }
    // trait du moment survolé (une ligne du journal)
    var cc = g.cursor - (g.values.length - cols)
    if (g.cursor >= 0 && cc >= 0 && cc < cols) {
      ctx.fillStyle = g.cursorColor
      ctx.fillRect(cc * g.step, g.notch, 1, g.height - g.notch)
    }
  }
}
