import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Journal des événements d'Ardoise : ouvertures, fermetures, fuites et alertes sur 1 h, 24 h ou 48 h.
// En haut, la mémoire utilisée avec une encoche par événement ; en bas, la liste par jour
// et le détail de l'événement choisi. Toutes les données viennent du panneau (`hub`).
PanelWindow {
  id: ew
  property var hub: null
  property var screenRef: null

  screen: screenRef
  visible: hub !== null
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "ardoise-journal"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.68)
  readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property int cap: Style.font.caption
  readonly property int rowH: hub ? hub.rowH : 20
  readonly property int notchH: Style.space(12)

  function tx(fr, en) { return hub ? hub.t(fr, en) : fr }
  function go(n) { return hub ? hub.go(n) : "" }
  function glyphOf(kind) { return kind === "open" ? "▲" : kind === "close" ? "▼" : kind === "leak" ? "↗" : "!" }
  function signedGo(d) { return d === undefined || d === null ? "" : (d < 0 ? "−" : "+") + go(Math.abs(d)) }
  function dayLabel(t) {
    var d = new Date(t * 1000), today = new Date()
    var start = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime() / 1000
    if (t >= start) return tx("aujourd'hui", "today")
    if (t >= start - 86400) return tx("hier", "yesterday")
    return String(d.getDate()).padStart(2, "0") + "/" + String(d.getMonth() + 1).padStart(2, "0")
  }

  // ── état ──
  property string period: hub && hub.eventsFocusT > 0 && Date.now() / 1000 - hub.eventsFocusT < 3500 ? "1h" : "24h"
  property string kindFilter: ""          // "" | open | close | leak | alert
  property string metric: "mem"           // courbe de la frise : mem | cpu | net | disk | gpu
  property real selectedT: hub ? hub.eventsFocusT : 0
  readonly property real span: ({ "1h": 3600, "24h": 86400, "48h": 172800 })[period]
  readonly property var periodEvents: {
    if (!hub) return []
    var from = Date.now() / 1000 - span
    return hub.events.filter(function(e) { return e.t >= from })
  }
  readonly property var shown: {
    var k = kindFilter
    return periodEvents.filter(function(e) { return k === "" || e.kind === k }).slice().reverse()
  }
  readonly property var counts: {
    var c = { open: 0, close: 0, leak: 0, alert: 0, freed: 0, lastAlert: 0 }
    periodEvents.forEach(function(e) {
      c[e.kind] = (c[e.kind] || 0) + 1
      if (e.kind === "close" && e.delta) c.freed += -e.delta
      if (e.kind === "alert") c.lastAlert = Math.max(c.lastAlert, e.t)
    })
    return c
  }
  readonly property var selected: {
    for (var i = 0; i < shown.length; i++) if (shown[i].t === selectedT) return shown[i]
    return shown.length ? shown[0] : null
  }
  // le groupe encore en vie qui porte le nom de l'événement (pour « montrer » et « terminer »)
  readonly property var liveGroup: {
    if (!hub || !hub.info || !selected || !selected.name) return null
    var gs = hub.info.groups
    for (var i = 0; i < gs.length; i++) if (gs[i].name === selected.name) return gs[i]
    return null
  }

  // repères sur la frise : une encoche par événement montré, le trait sur celui qui est choisi
  function marksFor(times) {
    if (!hub || !times || !times.length) return []
    var out = []
    for (var e = 0; e < shown.length; e++) {
      var t = shown[e].t
      if (t < times[0] - span / times.length || t > times[times.length - 1] + 60) continue
      var i = 0
      while (i < times.length - 1 && times[i] < t) i++
      out.push({ i: i, color: hub.eventColor(shown[e].kind), glyph: glyphOf(shown[e].kind), p: ({ alert: 4, leak: 3, close: 2, open: 1 })[shown[e].kind] || 0 })
    }
    return out
  }
  function indexOf(times, t) {
    if (!t || !times || !times.length) return -1
    var i = 0
    while (i < times.length - 1 && times[i] < t) i++
    return i
  }

  // voile : un clic en dehors ferme le journal
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.35)
    MouseArea { anchors.fill: parent; onClicked: ew.hub.closeEvents() }
  }

  Rectangle {
    id: card
    width: Math.min(parent.width - Style.space(80), Style.space(1180))
    height: Math.min(parent.height - Style.space(80), Style.space(800))
    anchors.centerIn: parent
    radius: Style.space(14)
    color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.99)
    border.color: Commons.Color.accent
    border.width: Math.max(1, Style.space(2))
    MouseArea { anchors.fill: parent }

    Item {
      anchors.fill: parent
      focus: true
      Component.onCompleted: forceActiveFocus()
      Keys.onEscapePressed: ew.hub.closeEvents()
    }

    Column {
      id: col
      x: Style.space(18); y: Style.space(14)
      width: card.width - Style.space(36)
      spacing: Style.space(10)

      // ── en-tête : titre, période, fermer ──
      Item {
        width: parent.width; height: Style.space(34)
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(14)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: ew.tx("ÉVÉNEMENTS", "EVENTS")
            color: ew.fg
            font.family: Style.font.family; font.pixelSize: Style.font.display; font.bold: true; font.letterSpacing: 3
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(20); radius: Style.space(5)
            width: periodRow.implicitWidth
            color: "transparent"; border.color: Qt.rgba(ew.fg.r, ew.fg.g, ew.fg.b, 0.14)
            clip: true
            Row {
              id: periodRow
              height: parent.height
              Repeater {
                model: [{ k: "1h", t: "1 h" }, { k: "24h", t: "24 h" }, { k: "48h", t: "48 h" }]
                Rectangle {
                  readonly property bool on: ew.period === modelData.k
                  height: parent.height; width: pLabel.implicitWidth + Style.space(18)
                  color: on ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.18) : "transparent"
                  RqText { id: pLabel; anchors.centerIn: parent; text: modelData.t; color: parent.on ? Commons.Color.accent : ew.dim; font.pixelSize: ew.cap }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ew.period = modelData.k }
                }
              }
            }
          }
        }
        RqText {
          anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          text: "×"; font.pixelSize: Style.font.body; color: closeMa.containsMouse ? Commons.Color.accent : ew.dim
          MouseArea { id: closeMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ew.hub.closeEvents() }
        }
      }

      // ── résumé en une phrase ──
      RqText {
        width: parent.width
        color: ew.dim; font.pixelSize: ew.cap
        text: {
          var c = ew.counts, parts = []
          parts.push(c.open + ew.tx(c.open > 1 ? " ouvertures" : " ouverture", c.open > 1 ? " openings" : " opening"))
          parts.push(c.close + ew.tx(c.close > 1 ? " fermetures" : " fermeture", c.close > 1 ? " closings" : " closing")
                     + (c.freed > 0 ? ew.tx(" (" + ew.go(c.freed) + " rendus)", " (" + ew.go(c.freed) + " freed)") : ""))
          parts.push(c.leak + ew.tx(c.leak > 1 ? " fuites" : " fuite", c.leak > 1 ? " leaks" : " leak"))
          parts.push(c.alert + ew.tx(c.alert > 1 ? " alertes" : " alerte", c.alert > 1 ? " alerts" : " alert")
                     + (c.lastAlert ? ew.tx(" (dernière à ", " (last at ") + ew.hub.hhmm(c.lastAlert) + ")" : ""))
          return ew.tx("sur ", "over ") + ({ "1h": "1 h", "24h": "24 h", "48h": "48 h" })[ew.period] + " : " + parts.join(" · ")
        }
      }

      // ── frise : une courbe au choix (mémoire par propriétaire, cpu, réseau, disque, gpu),
      //    une encoche par événement ──
      RqBox {
        width: parent.width
        title: ""
        aside: ew.tx("clic sur une encoche : l'événement", "click a notch: pick the event")
        Row {
          height: ew.rowH
          spacing: Style.space(6)
          Repeater {
            model: [{ k: "mem", t: ew.tx("mémoire", "memory") }, { k: "cpu", t: "cpu" }, { k: "net", t: ew.tx("réseau", "network") },
                    { k: "disk", t: ew.tx("disque", "disk") }, { k: "gpu", t: "gpu" }]
            Rectangle {
              readonly property bool on: ew.metric === modelData.k
              anchors.verticalCenter: parent.verticalCenter
              height: Style.space(20); radius: Style.space(5)
              width: mLabel.implicitWidth + Style.space(16)
              color: on ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.18) : "transparent"
              border.color: on ? Commons.Color.accent : Qt.rgba(ew.fg.r, ew.fg.g, ew.fg.b, 0.14)
              RqText { id: mLabel; anchors.centerIn: parent; text: modelData.t; color: parent.on ? Commons.Color.accent : ew.dim; font.pixelSize: ew.cap; font.bold: parent.on }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ew.metric = modelData.k }
            }
          }
        }
        Item { width: 1; height: Style.space(4) }
        RqChartFrame {
          id: frame
          hub: ew.hub; notchH: ew.notchH
          readonly property var topLabel: {
            if (!ew.hub) return ""
            if (ew.metric === "mem") return ew.hub.sys ? ew.hub.go(ew.hub.sys.total) : ""
            if (ew.metric === "net" || ew.metric === "disk") return ew.hub.rate(Math.max.apply(null, strip.values.concat(strip.values2, [1])))
            return "100 %"
          }
          yTop: topLabel; yMid: ew.metric === "cpu" || ew.metric === "gpu" ? "50 %" : ""; yBottom: "0"
          plotHeight: Style.space(80)
          times: {
            var lbl = ew.hub ? ew.hub.t("maintenant", "now") : ""
            return ew.period === "48h" ? ["−48 h", "−24 h", lbl] : ew.period === "24h" ? ["−24 h", "−12 h", lbl] : ["−1 h", "−30 min", lbl]
          }
          Item {
            id: plot
            width: parent.width; y: -ew.notchH; height: parent.height + ew.notchH
            readonly property int cols: Math.floor(width / 4)
            readonly property var times: ew.hub ? ew.hub.buckets(ew.metric === "mem" ? "parts" : ew.metric === "net" ? "rx" : ew.metric === "disk" ? "rd" : ew.metric, cols, ew.span).times : []
            readonly property var marks: ew.marksFor(times)
            readonly property int cur: ew.indexOf(times, ew.selected ? ew.selected.t : 0)
            RqStackGraph {
              id: memStrip
              visible: ew.metric === "mem"
              anchors.fill: parent; notch: ew.notchH
              values: visible && ew.hub ? ew.hub.buckets("parts", plot.cols, ew.span).vals : []
              maxValue: ew.hub && ew.hub.sys ? ew.hub.sys.total : 1
              threshold: ew.hub ? ew.hub.setting("alertThreshold", 85) / 100 : 0
              colors: ew.hub ? [ew.hub.cSessions, ew.hub.cApps, ew.hub.cFiles, ew.hub.cKernel, Qt.rgba(ew.fg.r, ew.fg.g, ew.fg.b, 0.18)] : []
              marks: visible ? plot.marks : []
              cursor: plot.cur
            }
            RqGraph {
              id: strip
              visible: ew.metric !== "mem"
              anchors.fill: parent; notch: ew.notchH
              readonly property string k1: ew.metric === "net" ? "rx" : ew.metric === "disk" ? "rd" : ew.metric
              readonly property string k2: ew.metric === "net" ? "tx" : ew.metric === "disk" ? "wr" : ""
              values: visible && ew.hub ? ew.hub.buckets(k1, plot.cols, ew.span).vals : []
              values2: visible && ew.hub && k2 ? ew.hub.buckets(k2, plot.cols, ew.span).vals : []
              maxValue: ew.metric === "cpu" || ew.metric === "gpu" ? 100 : 0
              tint: !ew.hub ? Commons.Color.accent : ew.metric === "cpu" ? ew.hub.cApps : ew.metric === "net" ? ew.hub.cNet : ew.metric === "disk" ? ew.hub.cFiles : ew.hub.cGpu
              tint2: !ew.hub ? Commons.Color.accent : ew.metric === "net" ? Commons.Color.accent : ew.hub.cGpu
              marks: visible ? plot.marks : []
              cursor: plot.cur
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: function(mouse) {
                // l'événement montré le plus proche de la colonne cliquée
                var times = plot.times
                var i = Math.floor(mouse.x / 4)
                if (i < 0 || i >= times.length) return
                var t = times[i], best = null
                for (var e = 0; e < ew.shown.length; e++)
                  if (!best || Math.abs(ew.shown[e].t - t) < Math.abs(best.t - t)) best = ew.shown[e]
                if (best) ew.selectedT = best.t
              }
            }
          }
        }
        // légende de la courbe choisie, avec les mêmes couleurs que la fenêtre principale
        Flow {
          width: parent.width
          spacing: Style.space(12)
          topPadding: Style.space(4)
          Repeater {
            model: {
              var h = ew.hub
              if (!h) return []
              if (ew.metric === "mem") return [{ c: h.cSessions, t: ew.tx("sessions ", "sessions ") + h.go(h.sessionsTotal) }, { c: h.cApps, t: ew.tx("applis ", "apps ") + h.go(h.appsTotal) },
                                               { c: h.cFiles, t: "/tmp " + h.go(h.filesTotal) }, { c: h.cKernel, t: ew.tx("noyau ", "kernel ") + h.go(h.kernelTotal) },
                                               { c: Qt.rgba(ew.fg.r, ew.fg.g, ew.fg.b, 0.35), t: ew.tx("écart ", "gap ") + h.go(h.ecart) },
                                               { c: Commons.Color.urgent, t: ew.tx("pointillé : seuil d'alerte", "dotted line: alert threshold") }]
              if (ew.metric === "net") return [{ c: h.cNet, t: ew.tx("↓ reçu", "↓ received") }, { c: Commons.Color.accent, t: ew.tx("↑ envoyé", "↑ sent") }]
              if (ew.metric === "disk") return [{ c: h.cFiles, t: ew.tx("lu", "read") }, { c: h.cGpu, t: ew.tx("écrit", "written") }]
              if (ew.metric === "cpu") return [{ c: h.cApps, t: ew.tx("charge moyenne de la tranche", "average load of the slot") }]
              return [{ c: h.cGpu, t: ew.tx("charge du GPU", "GPU load") }]
            }
            Row {
              spacing: Style.space(4)
              Rectangle { width: 7; height: 7; radius: 2; color: modelData.c; anchors.verticalCenter: parent.verticalCenter }
              RqText { text: modelData.t; color: ew.dim; font.pixelSize: ew.cap }
            }
          }
        }
      }

      // ── filtres par genre ──
      Row {
        spacing: Style.space(8)
        Repeater {
          model: [{ k: "", t: ew.tx("tout", "all"), n: ew.periodEvents.length },
                  { k: "open", t: ew.tx("▲ ouvertures", "▲ openings"), n: ew.counts.open },
                  { k: "close", t: ew.tx("▼ fermetures", "▼ closings"), n: ew.counts.close },
                  { k: "leak", t: ew.tx("↗ fuites", "↗ leaks"), n: ew.counts.leak },
                  { k: "alert", t: ew.tx("! alertes", "! alerts"), n: ew.counts.alert }]
          Rectangle {
            readonly property bool on: ew.kindFilter === modelData.k
            height: Style.space(22); radius: height / 2
            width: chipText.implicitWidth + Style.space(20)
            color: on ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.15) : "transparent"
            border.color: on ? Commons.Color.accent : Qt.rgba(ew.fg.r, ew.fg.g, ew.fg.b, 0.14)
            RqText {
              id: chipText; anchors.centerIn: parent
              text: modelData.t + "  " + modelData.n
              color: modelData.k === "" ? (parent.on ? Commons.Color.accent : ew.fg) : ew.hub ? ew.hub.eventColor(modelData.k) : ew.fg
              font.pixelSize: ew.cap
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ew.kindFilter = parent.on ? "" : modelData.k }
          }
        }
      }

      // ── liste par jour + détail ──
      Item {
        id: bottom
        width: parent.width
        height: card.height - y - Style.space(28)
        readonly property real detailW: Math.min(Style.space(360), width * 0.38)

        Rectangle {
          id: listBox
          width: bottom.width - bottom.detailW - Style.space(12); height: parent.height
          radius: Style.space(9)
          color: Qt.rgba(ew.fg.r, ew.fg.g, ew.fg.b, 0.05)
          border.color: ew.line
          readonly property real cTime: Style.space(52)
          readonly property real cGlyph: Style.space(16)
          readonly property real cEff: Style.space(84)
          readonly property real cRam: Style.space(84)

          Row {
            id: listHead
            x: Style.space(10); y: Style.space(8)
            height: ew.rowH
            spacing: Style.space(8)
            RqText { width: listBox.cTime; text: ew.tx("heure", "time"); color: ew.dim; font.pixelSize: ew.cap }
            RqText { width: listBox.cGlyph; text: "" }
            RqText { width: listBox.width - Style.space(20) - listBox.cTime - listBox.cGlyph - listBox.cEff - listBox.cRam - Style.space(32); text: ew.tx("événement", "event"); color: ew.dim; font.pixelSize: ew.cap }
            RqText { width: listBox.cEff; text: ew.tx("effet", "effect"); color: ew.dim; font.pixelSize: ew.cap; horizontalAlignment: Text.AlignRight }
            RqText { width: listBox.cRam; text: ew.tx("RAM alors", "RAM then"); color: ew.dim; font.pixelSize: ew.cap; horizontalAlignment: Text.AlignRight }
          }
          RqText {
            anchors.centerIn: parent
            visible: ew.shown.length === 0
            text: ew.tx("Aucun événement sur cette période.", "No event in this period.")
            color: ew.dim; font.pixelSize: ew.cap
          }
          ListView {
            id: list
            x: Style.space(4); y: listHead.y + listHead.height + Style.space(2)
            width: parent.width - Style.space(8); height: parent.height - y - Style.space(6)
            clip: true
            model: ew.shown
            boundsBehavior: Flickable.StopAtBounds
            delegate: Column {
              width: list.width
              readonly property bool newDay: index === 0 || ew.dayLabel(ew.shown[index - 1].t) !== ew.dayLabel(modelData.t)
              RqText {
                visible: parent.newDay
                height: visible ? ew.rowH : 0
                x: Style.space(6)
                text: ew.dayLabel(modelData.t).toUpperCase()
                color: ew.dim; font.pixelSize: Math.max(8, ew.cap - 1); font.letterSpacing: 1
              }
              Rectangle {
                readonly property bool sel: ew.selected && ew.selected.t === modelData.t && ew.selected.kind === modelData.kind
                width: parent.width; height: ew.rowH + Style.space(4)
                radius: Style.space(5)
                color: sel ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)
                     : rowMa.containsMouse ? Qt.rgba(ew.fg.r, ew.fg.g, ew.fg.b, 0.05) : "transparent"
                border.color: sel ? Commons.Color.accent : "transparent"
                Row {
                  x: Style.space(6); height: parent.height
                  spacing: Style.space(8)
                  RqText { width: listBox.cTime; height: parent.height; text: ew.hub.hhmm(modelData.t); color: ew.dim; font.pixelSize: ew.cap }
                  RqText { width: listBox.cGlyph; height: parent.height; text: ew.glyphOf(modelData.kind); color: ew.hub.eventColor(modelData.kind); font.bold: true; font.pixelSize: ew.cap }
                  RqText { width: listBox.width - Style.space(20) - listBox.cTime - listBox.cGlyph - listBox.cEff - listBox.cRam - Style.space(32); height: parent.height; text: modelData.text; font.pixelSize: ew.cap }
                  RqText {
                    width: listBox.cEff; height: parent.height; horizontalAlignment: Text.AlignRight; font.pixelSize: ew.cap
                    text: modelData.kind === "leak" && modelData.slope ? "+" + ew.go(modelData.slope) + "/h" : ew.signedGo(modelData.delta)
                    color: modelData.delta < 0 ? ew.hub.cApps : modelData.delta > 0 || modelData.kind === "leak" ? ew.hub.cFiles : ew.dim
                  }
                  RqText { width: listBox.cRam; height: parent.height; horizontalAlignment: Text.AlignRight; font.pixelSize: ew.cap; color: ew.dim; text: modelData.used ? ew.go(modelData.used) : "" }
                }
                MouseArea { id: rowMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ew.selectedT = modelData.t }
              }
            }
          }
        }

        // ── détail de l'événement choisi ──
        Rectangle {
          x: listBox.width + Style.space(12)
          width: bottom.detailW; height: parent.height
          radius: Style.space(9)
          color: Qt.rgba(ew.fg.r, ew.fg.g, ew.fg.b, 0.05)
          border.color: ew.line
          readonly property var e: ew.selected

          Column {
            visible: !!parent.e
            x: Style.space(12); y: Style.space(10)
            width: parent.width - Style.space(24)
            spacing: Style.space(8)
            readonly property var e: parent.e

            Row {
              width: parent.width
              spacing: Style.space(8)
              RqText { text: parent.parent.e ? ew.glyphOf(parent.parent.e.kind) : ""; color: parent.parent.e ? ew.hub.eventColor(parent.parent.e.kind) : ew.fg; font.bold: true }
              RqText {
                width: parent.width - Style.space(90)
                text: {
                  var e = parent.parent.e
                  if (!e) return ""
                  var k = { open: ew.tx("ouverture", "opening"), close: ew.tx("fermeture", "closing"), leak: ew.tx("fuite", "leak"), alert: ew.tx("alerte", "alert") }[e.kind]
                  return k + (e.name ? " · " + e.name : "")
                }
                font.bold: true
              }
              RqText { text: parent.parent.e ? ew.dayLabel(parent.parent.e.t) + " " + ew.hub.hhmm(parent.parent.e.t) : ""; color: ew.dim; font.pixelSize: ew.cap }
            }
            RqText {
              width: parent.width
              wrapMode: Text.WordWrap; elide: Text.ElideNone
              color: ew.dim; font.pixelSize: ew.cap
              text: {
                var e = parent.e
                if (!e) return ""
                if (e.kind === "leak") return ew.tx("Sa mémoire monte sans redescendre depuis 30 min. Ce n'est pas forcément un bug : un serveur de dev qui recompile peut grossir ainsi.",
                                                     "Its memory has kept rising for 30 min. Not always a bug: a dev server that keeps recompiling can grow like this.")
                if (e.kind === "alert") return e.detail || e.text
                if (e.kind === "open") return e.group === "claude" ? ew.tx("Une session Claude Code a démarré.", "A Claude Code session started.") : ew.tx("Un programme a démarré.", "A program started.")
                return e.group === "claude" ? ew.tx("La session s'est arrêtée ; sa mémoire est rendue.", "The session stopped; its memory was freed.")
                                            : ew.tx("Le programme s'est arrêté ; sa mémoire est rendue.", "The program stopped; its memory was freed.")
              }
            }
            // la courbe d'une fuite : sa mémoire sur la demi-heure qui l'a fait repérer
            RqText {
              visible: !!parent.e && !!parent.e.series && parent.e.series.length > 1
              text: ew.tx("sa mémoire, la demi-heure avant l'alerte", "its memory, the half hour before the alert")
              color: ew.dim; font.pixelSize: Math.max(8, ew.cap - 1)
            }
            RqGraph {
              visible: !!parent.e && !!parent.e.series && parent.e.series.length > 1
              width: parent.width; height: visible ? Style.space(56) : 0
              values: parent.e && parent.e.series ? parent.e.series.map(function(p) { return p[1] }) : []
              tint: ew.hub ? ew.hub.cFiles : Commons.Color.accent
            }
            Repeater {
              model: {
                var e = parent.e
                if (!e) return []
                var r = []
                if (e.kind === "leak") {
                  if (e.slope) r.push([ew.tx("pente", "slope"), "+" + ew.go(e.slope) + ew.tx("/h", "/h")])
                  if (e.series && e.series.length > 1) r.push([ew.tx("en 30 min", "in 30 min"), ew.go(e.series[0][1]) + " → " + ew.go(e.series[e.series.length - 1][1])])
                  if (e.pids && e.pids.length) r.push([ew.tx("processus", "process"), "pid " + e.pids.slice(0, 3).join(", ")])
                  r.push([ew.tx("aujourd'hui", "now"), ew.liveGroup ? ew.go(ew.liveGroup.ram + ew.liveGroup.zram) + (ew.liveGroup.leak ? ew.tx(" · toujours en hausse", " · still rising") : "") : ew.tx("arrêté", "stopped")])
                } else if (e.kind === "alert") {
                  if (e.pct) r.push([ew.tx("RAM", "RAM"), e.pct + " %"])
                } else {
                  if (e.delta) r.push([ew.tx("effet", "effect"), ew.signedGo(e.delta)])
                  r.push([ew.tx("genre", "kind"), e.group === "claude" ? ew.tx("session Claude", "Claude session") : ew.tx("appli", "app")])
                  if (e.kind === "open") r.push([ew.tx("aujourd'hui", "now"), ew.liveGroup ? ew.tx("toujours là · ", "still running · ") + ew.go(ew.liveGroup.ram + ew.liveGroup.zram) : ew.tx("fermé depuis", "closed since")])
                }
                if (e.used) r.push([ew.tx("RAM utilisée alors", "RAM in use then"), ew.go(e.used)])
                return r
              }
              Item {
                width: parent.width; height: ew.rowH + Style.space(2)
                Rectangle { width: parent.width; height: 1; color: ew.line }
                RqText { y: Style.space(2); height: ew.rowH; text: modelData[0]; color: ew.dim; font.pixelSize: ew.cap }
                RqText { anchors.right: parent.right; y: Style.space(2); height: ew.rowH; width: parent.width * 0.62; horizontalAlignment: Text.AlignRight; text: modelData[1]; font.pixelSize: ew.cap }
              }
            }
            Flow {
              width: parent.width
              spacing: Style.space(14)
              RqAct {
                hub: ew.hub; label: ew.tx("voir sur la courbe", "show on the chart")
                onActivated: ew.hub.showMoment(parent.parent.e.t)
              }
              RqAct {
                hub: ew.hub; label: ew.tx("montrer le processus", "show the process")
                visible: !!ew.liveGroup
                onActivated: { var n = ew.liveGroup.name; ew.hub.closeEvents(); if (!ew.hub.windowOpen) ew.hub.openWindow(); ew.hub.search = n }
              }
              RqAct {
                hub: ew.hub; key: "ev-term"; confirm: true; danger: true
                label: ew.tx("terminer", "terminate")
                visible: !!ew.liveGroup && !ew.liveGroup.protected && !!parent.parent.e && parent.parent.e.kind === "leak"
                onActivated: ew.hub.run(["action", "terminer"].concat(ew.liveGroup.roots.map(String)), ew.liveGroup.name + ew.tx(" terminé", " terminated"))
              }
            }
          }
          RqText {
            anchors.centerIn: parent
            visible: !parent.e
            text: ew.tx("Choisis un événement.", "Pick an event.")
            color: ew.dim; font.pixelSize: ew.cap
          }
        }
      }
    }
  }
}
