import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Fenêtre centrée de Ardoise, façon Boxtop en paysage.
// À gauche : cpu, mémoire, réseau, disque, carte graphique, avec leurs historiques.
// À droite : tous les processus regroupés (recherche, tri, actions) et l'analyse avec Claude.
// Toutes les données viennent du panneau (`hub`), qui garde le flux ardoise.
PanelWindow {
  id: win
  property var hub: null
  property var screenRef: null

  screen: screenRef
  visible: hub !== null
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "ardoise"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.68)   // 4,5:1 sur le fond, même en petit
  readonly property color faint: Qt.rgba(fg.r, fg.g, fg.b, 0.18)
  readonly property int cap: Style.font.caption
  readonly property int rowH: hub ? hub.rowH : 20
  readonly property real gap: Style.space(10)

  function go(n) { return hub ? hub.go(n) : "" }
  // texte dans la langue du panneau (réglage `language`)
  function tx(fr, en) { return hub ? hub.t(fr, en) : fr }
  readonly property bool hasClaude: !!hub && hub.hasClaude

  // Colonnes du tableau : position et largeur en fraction de la largeur.
  readonly property var columns: [
    { k: "name", t: tx("groupe / processus", "group / process"), x: 0.00, w: 0.27, r: false },
    { k: "procs", t: "proc", x: 0.27, w: 0.05, r: true },
    { k: "cpu", t: "CPU", x: 0.32, w: 0.06, r: true },
    { k: "ram", t: "RAM", x: 0.38, w: 0.08, r: true },
    { k: "pct", t: tx("% de la RAM", "% of RAM"), x: 0.46, w: 0.13, r: false },
    { k: "tmp", t: "/tmp", x: 0.59, w: 0.06, r: true },
    { k: "idle", t: tx("calme", "idle"), x: 0.65, w: 0.08, r: false },
    { k: "poids", t: tx("poids", "weight"), x: 0.73, w: 0.05, r: true },
    { k: "", t: "", x: 0.79, w: 0.21, r: false }
  ]
  function col(k) {
    for (var i = 0; i < columns.length; i++) if (columns[i].k === k) return columns[i]
    return columns[columns.length - 1]
  }
  function cx(k, item) { return item.width * col(k).x }
  function cw(k, item) { return item.width * col(k).w - 6 }
  // Part de la RAM utilisée (MemTotal - MemAvailable).
  readonly property real used: hub && hub.info ? hub.info.used : 1
  function share(v) {
    var p = 100 * v / used
    return p >= 10 ? Math.round(p) + " %" : p >= 0.1 ? (hub ? hub.num(p, 1) : p.toFixed(1)) + " %" : "—"
  }

  function glyphOf(kind) { return kind === "open" ? "▲" : kind === "close" ? "▼" : kind === "leak" ? "↗" : "!" }
  // Repères : pour chaque événement de la plage, l'index de la colonne où il tombe.
  function marksFor(times) {
    if (!hub || !times || !times.length) return []
    var evs = hub.rangeEvents(), out = []
    for (var e = 0; e < evs.length; e++) {
      var t = evs[e].t
      if (t < times[0] - 60 || t > times[times.length - 1] + 60) continue
      var i = 0
      while (i < times.length - 1 && times[i] < t) i++
      out.push({ i: i, color: hub.eventColor(evs[e].kind), glyph: glyphOf(evs[e].kind) })
    }
    return out
  }

  // ── info-bulle ──
  property string tipTitle: ""
  property string tipBody: ""
  property var tipItem: null
  property bool tipShown: false
  function queueTip(title, body, item) {
    var already = tipShown || graceTimer.running
    tipTitle = title; tipBody = body; tipItem = item
    if (body === "") { tipShown = false; return }
    if (already) { tipShown = true; return }   // on glisse d'une ligne à l'autre : tout de suite
    tipShown = false
    tipTimer.restart()
  }
  function hideTip() { if (tipShown) graceTimer.restart(); tipTimer.stop(); tipShown = false; tipItem = null }
  Timer { id: graceTimer; interval: 300 }
  // Une ligne que la souris quitte n'efface que sa propre info-bulle : en passant
  // d'une ligne à l'autre, l'entrée dans la nouvelle peut arriver avant la sortie.
  function leaveTip(item) { if (tipItem === item) hideTip() }
  // Info-bulle des graphiques à points (cpu, réseau, disque, gpu) : l'heure, la valeur
  // de la colonne survolée et les événements (repères) qui y tombent.
  function graphTip(g, x, key) {
    var h = hub
    if (!h || !g.values.length) return
    var i = g.values.length - g.cols + Math.floor(x / g.step)
    if (i < 0 || i >= g.values.length) { leaveTip(g); return }
    var times = h.seriesTimes(key, g.cols)
    var t = times[i], v = g.values[i], v2 = g.values2.length > i ? g.values2[i] : 0
    var title, line
    if (key === "rx") { title = "↓ " + h.rate(v) + "  ↑ " + h.rate(v2); line = h.t("réseau : reçu / envoyé", "network: received / sent") }
    else if (key === "rd") { title = h.t("lu ", "read ") + h.rate(v) + h.t("  écrit ", "  written ") + h.rate(v2); line = h.t("disque : lu / écrit", "disk: read / written") }
    else { title = h.pctTxt(v); line = key === "gpu" ? h.t("charge du GPU", "GPU load") : h.t("charge du processeur", "CPU load") }
    var span = h.range === "24h" ? 600 : h.range === "1h" ? 60 : 3
    var evs = h.events.filter(function(e) { return t && Math.abs(e.t - t) <= span })
    var body = line + (evs.length ? "\n" + evs.map(function(e) { return h.hhmm(e.t) + "  " + e.text }).join("\n") : "")
    queueTip((t ? h.hhmm(t) + " · " : "") + title, body, g)
  }
  Timer { id: tipTimer; interval: 450; onTriggered: win.tipShown = win.tipItem !== null }
  // La table garde ses lignes d'un relevé à l'autre (on déplace, ajoute, retire),
  // pour ne perdre ni le défilement, ni le survol, ni l'info-bulle.
  ListModel { id: rowsModel }
  function syncRows() {
    if (!hub) return
    var ids = hub.tableGroups.map(function(g) { return g.id })
    var want = {}
    for (var a = 0; a < ids.length; a++) want[ids[a]] = true
    for (var i = rowsModel.count - 1; i >= 0; i--)
      if (!want[rowsModel.get(i).gid]) rowsModel.remove(i)
    for (var j = 0; j < ids.length; j++) {
      if (j < rowsModel.count && rowsModel.get(j).gid === ids[j]) continue
      var found = -1
      for (var k = j + 1; k < rowsModel.count; k++) if (rowsModel.get(k).gid === ids[j]) { found = k; break }
      if (found >= 0) rowsModel.move(found, j, 1)
      else rowsModel.insert(j, { gid: ids[j] })
    }
  }
  onHubChanged: syncRows()

  Connections {
    target: win.hub
    function onTableGroupsChanged() { win.syncRows() }
    function onBulleDemandee(nom) {
      var rows = win.hub.tableGroups
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].name !== nom) continue
        list.positionViewAtIndex(i, ListView.Contain)
        var item = list.itemAtIndex(i)
        if (item) win.queueTip(rows[i].name, rows[i].desc || "", item)
        return
      }
    }
  }

  // voile : un clic en dehors de la carte ferme
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)
    MouseArea { anchors.fill: parent; onClicked: win.hub.closeWindow() }
  }

  Rectangle {
    id: card
    width: Math.min(parent.width - Style.space(80), Style.space(1560))
    height: Math.min(parent.height - Style.space(80), Style.space(980))
    anchors.centerIn: parent
    radius: Style.space(14)
    color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.985)
    border.color: Commons.Color.popups.border
    border.width: Math.max(1, Style.space(2))
    MouseArea { anchors.fill: parent; onClicked: win.hub.armed = "" }

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: { if (win.hub.search !== "") win.hub.search = ""; else win.hub.closeWindow() }
      Keys.onPressed: function(e) {
        if (e.text === "/" ) { search.forceActiveFocus(); e.accepted = true }
      }
    }

    // ── en-tête : le nom, l'état général en une phrase, la recherche, les indicateurs ──
    Item {
      id: header
      x: Style.space(18); y: Style.space(14)
      width: card.width - Style.space(36)
      height: Style.space(48)

      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)
        Row {
          spacing: Style.space(12)
          Text {
            text: "ARDOISE"
            color: win.fg
            font.family: Style.font.family; font.pixelSize: Style.font.display; font.bold: true; font.letterSpacing: 3
          }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(22); radius: height / 2
            width: verdictRow.implicitWidth + Style.space(20)
            color: win.hub ? Qt.rgba(win.hub.verdictColor.r, win.hub.verdictColor.g, win.hub.verdictColor.b, 0.13) : "transparent"
            Row {
              id: verdictRow
              anchors.centerIn: parent
              spacing: Style.space(6)
              Rectangle { width: 7; height: 7; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: win.hub ? win.hub.verdictColor : win.fg }
              RqText { text: win.hub ? win.hub.verdict.text : ""; color: win.hub ? win.hub.verdictColor : win.fg }
            }
          }
        }
        RqText {
          width: header.width * 0.45
          color: win.dim; font.pixelSize: win.cap
          text: win.hub ? win.hub.verdict.detail : ""
        }
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(14)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(240); height: Style.space(30)
          clip: true
          radius: Style.space(8)
          color: Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.06)
          border.color: search.activeFocus ? Commons.Color.accent : Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.12)
          RqText {
            anchors.left: parent.left; anchors.leftMargin: Style.space(10); anchors.verticalCenter: parent.verticalCenter
            text: win.tx("chercher…", "search…")
            color: win.dim; visible: search.text === ""
            font.pixelSize: win.cap
          }
          TextInput {
            id: search
            anchors.fill: parent; anchors.leftMargin: Style.space(10); anchors.rightMargin: Style.space(30)
            verticalAlignment: TextInput.AlignVCenter
            color: win.fg
            font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
            clip: true
            text: win.hub ? win.hub.search : ""
            onTextEdited: win.hub.search = text
            Keys.onEscapePressed: { if (text !== "") { text = ""; win.hub.search = "" } else keys.forceActiveFocus() }
          }
          Rectangle {
            anchors.right: parent.right; anchors.rightMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter
            width: Style.space(16); height: Style.space(16); radius: 3
            color: "transparent"; border.color: Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.25)
            RqText { anchors.centerIn: parent; text: "/"; color: win.dim; font.pixelSize: win.cap }
          }
        }

        // indicateurs : le nom, la valeur et une mini-courbe des dernières secondes
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(18)
          Repeater {
            model: {
              var h = win.hub, sy = h ? h.sys : null
              if (!sy) return []
              var disk = sy.disks.length ? Math.round(100 * sy.disks[0].used / sy.disks[0].total) : 0
              var memPct = h.hMem
              var list = [
                { t: "cpu", v: Math.round(sy.cpu) + "%", c: h.cApps, hot: sy.cpu >= 90, w: 0, sp: h.spark(h.hCpu, 14), max: 100 },
                { t: "ram", v: h.pct + "%", c: h.cSessions, hot: h.pct >= 85, w: 0, sp: h.spark(memPct, 14), max: 100 },
                { t: win.tx("disque", "disk"), v: disk + "%", c: h.cFiles, hot: disk >= 90, w: 0, sp: h.spark(h.hWrite, 14), max: 0 }
              ]
              if (sy.gpu.busy !== null) list.push({ t: "gpu", v: sy.gpu.busy + "%", c: h.cGpu, hot: sy.gpu.busy >= 95, w: 0, sp: h.spark(h.hGpu, 14), max: 100 })
              // le réseau en dernier : sa largeur fixe (contre les sauts de chiffres) ne crée pas de trou
              list.push({ t: win.tx("réseau (par s)", "network (/s)"), v: "↓" + h.go(sy.net.rx) + " ↑" + h.go(sy.net.tx), c: h.cNet, hot: false, w: Style.space(150), sp: h.spark(h.hRx, 14), max: 0 })
              return list
            }
            Column {
              id: kpi
              readonly property var k: modelData
              readonly property real ceil: k.max > 0 ? k.max : Math.max(1, Math.max.apply(null, k.sp.length ? k.sp : [1]))
              width: k.w > 0 ? k.w : Math.max(kLabel.implicitWidth, kValue.implicitWidth, Style.space(44))
              spacing: 0
              RqText { id: kLabel; text: kpi.k.t; color: kpi.k.c; font.pixelSize: win.cap }
              Text {
                id: kValue
                text: kpi.k.v
                color: kpi.k.hot ? Commons.Color.urgent : win.fg
                font.family: Style.font.family; font.pixelSize: Style.font.heading; font.bold: true
              }
              Row {
                height: Style.space(8); spacing: 1
                Repeater {
                  model: kpi.k.sp
                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: 2; height: Math.max(1, Math.round(Style.space(8) * Math.min(1, modelData / kpi.ceil)))
                    color: kpi.k.c; opacity: 0.85
                  }
                }
              }
            }
          }
        }
        RqAct {
          anchors.verticalCenter: parent.verticalCenter
          hub: win.hub; label: "✕"; font.pixelSize: Style.font.title
          onActivated: win.hub.closeWindow()
        }
      }
    }

    // ── colonne de gauche : les mesures ──
    Column {
      id: left
      x: Style.space(18)
      y: header.y + header.height + Style.space(12)
      width: (card.width - Style.space(36)) * 0.36
      spacing: win.gap

      // plage d'historique + légende des repères
      Item {
        width: parent.width; height: win.rowH
        Row {
          height: parent.height
          spacing: Style.space(10)
          RqText { height: parent.height; text: win.tx("historique", "history"); color: win.dim; font.pixelSize: win.cap }
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(18); radius: Style.space(5)
            width: rangeRow.implicitWidth
            color: "transparent"; border.color: Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.14)
            clip: true
            Row {
              id: rangeRow
              height: parent.height
              Repeater {
                model: [{ k: "live", t: "5 min" }, { k: "1h", t: "1 h" }, { k: "24h", t: "24 h" }]
                Rectangle {
                  readonly property bool on: win.hub && win.hub.range === modelData.k
                  height: parent.height; width: rangeLabel.implicitWidth + Style.space(18)
                  color: on ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.18) : "transparent"
                  RqText { id: rangeLabel; anchors.centerIn: parent; text: modelData.t; color: parent.on ? Commons.Color.accent : win.dim; font.pixelSize: win.cap }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.hub.range = modelData.k }
                }
              }
            }
          }
          RqText {
            height: parent.height
            visible: !!win.hub && win.hub.range !== "live" && win.hub.minutes.length < 5
            text: win.tx("se remplit : un point par minute", "filling up: one point per minute")
            color: win.dim; font.pixelSize: win.cap
          }
        }
        Row {
          anchors.right: parent.right
          height: parent.height
          spacing: Style.space(8)
          RqText { height: parent.height; text: win.tx("repères", "markers"); color: win.dim; font.pixelSize: win.cap }
          Repeater {
            model: win.hub ? [{ t: win.tx("▲ ouvert", "▲ opened"), k: "open" }, { t: win.tx("▼ fermé", "▼ closed"), k: "close" }, { t: win.tx("↗ fuite", "↗ leak"), k: "leak" }, { t: win.tx("! alerte", "! alert"), k: "alert" }] : []
            RqText { height: parent.height; text: modelData.t; color: win.hub.eventColor(modelData.k); font.pixelSize: win.cap }
          }
        }
      }

      // ¹ cpu : la courbe et une bande de 16 cases, une par cœur
      RqBox {
        width: parent.width
        num: "¹"; title: "cpu"
        subtitle: win.hub && win.hub.hw.cpu ? win.hub.hw.cpu : ""
        aside: win.hub && win.hub.sys ? win.hub.pctTxt(win.hub.sys.cpu) + (win.hub.sys.cpu_temp ? " · " + Math.round(win.hub.sys.cpu_temp) + "°" : "") : ""
        RqChartFrame {
          hub: win.hub; yTop: "100"; yMid: "50"; yBottom: "0"
          plotHeight: Style.space(118)
          RqGraph {
            width: parent.width; height: parent.height
            values: win.hub ? win.hub.series("cpu", cols) : []
            MouseArea { anchors.fill: parent; hoverEnabled: true; onExited: win.leaveTip(parent); onPositionChanged: function(mouse) { win.graphTip(parent, mouse.x, "cpu") } }
            marks: win.marksFor(win.hub ? win.hub.seriesTimes("cpu", cols) : [])
            maxValue: 100
            tint: win.hub ? win.hub.cApps : "white"
          }
        }
        Item { width: 1; height: Style.space(6) }
        Item {
          width: parent.width; height: Style.space(18)
          readonly property var cores: win.hub && win.hub.sys ? win.hub.sys.cores : []
          readonly property int hot: cores.length ? cores.indexOf(Math.max.apply(null, cores)) : -1
          RqText { id: coresLabel; height: parent.height; text: win.tx("cœurs", "cores"); color: win.dim; font.pixelSize: win.cap }
          RqText {
            id: coresMax
            anchors.right: parent.right; height: parent.height
            text: parent.hot >= 0 ? "max " + Math.round(parent.cores[parent.hot]) + " % (C" + parent.hot + ")" : ""
            color: win.dim; font.pixelSize: win.cap
          }
          Row {
            id: coreRow
            x: coresLabel.implicitWidth + Style.space(8)
            width: parent.width - x - coresMax.implicitWidth - Style.space(10)
            height: parent.height
            spacing: 3
            Repeater {
              model: parent.parent.cores
              Rectangle {
                id: coreCell
                width: (coreRow.width - 3 * Math.max(0, coreRow.parent.cores.length - 1)) / Math.max(1, coreRow.parent.cores.length)
                height: coreRow.height; radius: 3
                // vert de plus en plus franc, puis orange et rouge quand le cœur sature
                color: modelData >= 90 ? Commons.Color.urgent : modelData >= 70 ? win.hub.cFiles
                  : Qt.rgba(0.56, 0.75, 0.50, 0.15 + Math.min(1, modelData / 50) * 0.85)
                border.color: coreMa.containsMouse ? win.fg : "transparent"
                MouseArea {
                  id: coreMa
                  anchors.fill: parent; hoverEnabled: true
                  onContainsMouseChanged: containsMouse ? win.queueTip(win.tx("cœur C", "core C") + index, Math.round(modelData) + win.tx(" % d'utilisation", " % used"), coreCell) : win.leaveTip(coreCell)
                }
              }
            }
          }
        }
      }

      // ² mémoire : la répartition dans le temps, avec le seuil d'alerte
      RqBox {
        width: parent.width
        num: "²"; title: win.tx("mémoire", "memory")
        subtitle: win.hub && win.hub.hw.mem ? win.hub.hw.mem : ""
        aside: win.hub && win.hub.sys ? go(win.hub.sys.used) + " / " + go(win.hub.sys.total) : ""
        RqChartFrame {
          hub: win.hub
          yTop: win.hub && win.hub.sys ? go(win.hub.sys.total) : ""
          yMid: win.hub && win.hub.sys ? go(win.hub.sys.total / 2) : ""
          yBottom: "0"
          plotHeight: Style.space(132)
          RqStackGraph {
            id: memGraph
            width: parent.width; height: parent.height
            values: win.hub ? win.hub.series("parts", cols) : []
            marks: win.marksFor(win.hub ? win.hub.seriesTimes("parts", cols) : [])
            maxValue: win.hub && win.hub.sys ? win.hub.sys.total : 1
            threshold: win.hub ? win.hub.setting("alertThreshold", 85) / 100 : 0
            colors: win.hub ? [win.hub.cSessions, win.hub.cApps, win.hub.cFiles, win.hub.cKernel, win.faint] : []
            // survol : l'heure, la répartition et les événements de la colonne
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onExited: win.leaveTip(memGraph)
              onPositionChanged: function(mouse) {
                var g = memGraph, h = win.hub
                if (!h || !g.values.length) return
                var c = Math.floor(mouse.x / g.step)
                var i = g.values.length - g.cols + c
                if (i < 0 || i >= g.values.length) { win.leaveTip(g); return }
                var times = h.seriesTimes("parts", g.cols)
                var t = times[i]
                var p = g.values[i]
                var tot = p.reduce(function(a, b) { return a + b }, 0)
                var body = "sessions " + h.go(p[0]) + h.t(" · applis ", " · apps ") + h.go(p[1]) + " · /tmp " + h.go(p[2])
                  + h.t(" · noyau ", " · kernel ") + h.go(p[3]) + h.t(" · écart ", " · gap ") + h.go(p[4])
                var span = h.range === "24h" ? 600 : h.range === "1h" ? 60 : 3
                var evs = h.events.filter(function(e) { return t && Math.abs(e.t - t) <= span })
                if (evs.length) body += "\n" + evs.map(function(e) { return h.hhmm(e.t) + "  " + e.text }).join("\n")
                win.queueTip((t ? h.hhmm(t) + " · " : "") + h.go(tot) + h.t(" utilisés", " used"), body, g)
              }
            }
          }
        }
        Item { width: 1; height: Style.space(6) }
        Row {
          id: stack
          width: parent.width
          height: Style.space(8)
          readonly property real used: win.hub && win.hub.info ? win.hub.info.used : 1
          Repeater {
            model: win.hub ? [
              { v: win.hub.sessionsTotal, c: win.hub.cSessions }, { v: win.hub.appsTotal, c: win.hub.cApps },
              { v: win.hub.filesTotal, c: win.hub.cFiles }, { v: win.hub.kernelTotal, c: win.hub.cKernel },
              { v: win.hub.ecart, c: win.faint }
            ] : []
            Rectangle { width: Math.max(0, stack.width * modelData.v / stack.used); height: stack.height; color: modelData.c; radius: 2 }
          }
        }
        Item { width: 1; height: Style.space(4) }
        Flow {
          width: parent.width
          spacing: Style.space(12)
          Repeater {
            model: win.hub ? [
              { t: "sessions", v: win.hub.sessionsTotal, c: win.hub.cSessions }, { t: win.tx("applis", "apps"), v: win.hub.appsTotal, c: win.hub.cApps },
              { t: "/tmp", v: win.hub.filesTotal, c: win.hub.cFiles }, { t: win.tx("noyau", "kernel"), v: win.hub.kernelTotal, c: win.hub.cKernel },
              { t: win.tx("écart", "gap"), v: win.hub.ecart, c: win.faint }
            ] : []
            Row {
              spacing: Style.space(4)
              Rectangle { width: 7; height: 7; radius: 2; color: modelData.c; anchors.verticalCenter: parent.verticalCenter }
              RqText { text: modelData.t + " " + go(modelData.v); color: win.dim; font.pixelSize: win.cap }
            }
          }
        }
        // derniers événements de la plage, avec le symbole de leur repère
        Repeater {
          model: win.hub ? win.hub.rangeEvents().slice(0, 3) : []
          Row {
            spacing: Style.space(6)
            height: Math.round(win.rowH * 0.85)
            RqText { height: parent.height; text: win.glyphOf(modelData.kind); color: win.hub.eventColor(modelData.kind); font.pixelSize: win.cap; font.bold: true }
            RqText { height: parent.height; text: win.hub.hhmm(modelData.t); color: win.dim; font.pixelSize: win.cap }
            RqText { height: parent.height; text: modelData.text; font.pixelSize: win.cap; width: memGraph.width - Style.space(40) }
          }
        }
        RqText {
          width: parent.width; height: win.rowH
          color: win.dim; font.pixelSize: win.cap
          text: win.hub && win.hub.sys && win.hub.sys.zram.data > 0
            ? win.tx("zram : ", "zram: ") + go(win.hub.sys.zram.data) + win.tx(" mis de côté, compressés en ", " set aside, compressed to ") + go(win.hub.sys.zram.used)
              + win.tx(" · pointillé rouge : seuil d'alerte", " · red dots: alert threshold")
            : win.tx("pointillé rouge : seuil d'alerte", "red dots: alert threshold")
        }
      }

      // ³ réseau et ⁴ disque, côte à côte
      Row {
        width: parent.width
        spacing: win.gap
        RqBox {
          width: (parent.width - win.gap) / 2
          num: "³"; title: win.tx("réseau", "network")
          aside: win.hub && win.hub.sys ? "↓ " + win.hub.rate(win.hub.sys.net.rx) : ""
          asideColor: win.hub ? win.hub.cNet : win.dim
          RqChartFrame {
            hub: win.hub
            yTop: win.hub ? win.hub.go(Math.max.apply(null, (win.hub.series("rx", 200).concat(win.hub.series("tx", 200), [1])))) : ""
            yMid: ""; yBottom: "0"
            plotHeight: Style.space(80)
            RqGraph {
              width: parent.width; height: parent.height
              values: win.hub ? win.hub.series("rx", cols) : []
              values2: win.hub ? win.hub.series("tx", cols) : []
            MouseArea { anchors.fill: parent; hoverEnabled: true; onExited: win.leaveTip(parent); onPositionChanged: function(mouse) { win.graphTip(parent, mouse.x, "rx") } }
              marks: win.marksFor(win.hub ? win.hub.seriesTimes("rx", cols) : [])
              tint: win.hub ? win.hub.cNet : "white"
              tint2: Commons.Color.accent
            }
          }
          RqText {
            width: parent.width; height: win.rowH
            font.pixelSize: win.cap; color: win.dim
            text: win.hub && win.hub.sys ? win.tx("↑ envoi ", "↑ upload ") + win.hub.rate(win.hub.sys.net.tx) + " (cyan) · " + (win.hub.hw.net || "") : ""
          }
        }
        RqBox {
          width: (parent.width - win.gap) / 2
          num: "⁴"; title: win.tx("disque", "disk")
          aside: win.hub && win.hub.sys ? win.tx("écrit ", "write ") + win.hub.rate(win.hub.sys.disk.write) : ""
          asideColor: win.hub ? win.hub.cGpu : win.dim
          RqChartFrame {
            hub: win.hub
            yTop: win.hub ? win.hub.go(Math.max.apply(null, (win.hub.series("rd", 200).concat(win.hub.series("wr", 200), [1])))) : ""
            yMid: ""; yBottom: "0"
            plotHeight: Style.space(80)
            RqGraph {
              width: parent.width; height: parent.height
              values: win.hub ? win.hub.series("rd", cols) : []
              values2: win.hub ? win.hub.series("wr", cols) : []
            MouseArea { anchors.fill: parent; hoverEnabled: true; onExited: win.leaveTip(parent); onPositionChanged: function(mouse) { win.graphTip(parent, mouse.x, "rd") } }
              marks: win.marksFor(win.hub ? win.hub.seriesTimes("rd", cols) : [])
              tint: win.hub ? win.hub.cFiles : "white"
              tint2: win.hub ? win.hub.cGpu : "white"
            }
          }
          Repeater {
            model: win.hub && win.hub.sys ? win.hub.sys.disks : []
            Item {
              width: parent.width; height: win.rowH
              RqText { width: parent.width * 0.62; text: modelData.model + " · " + modelData.path; font.pixelSize: win.cap }
              RqText { anchors.right: parent.right; text: Math.round(100 * modelData.used / modelData.total) + " %"; color: modelData.used / modelData.total >= 0.9 ? Commons.Color.urgent : win.dim; font.pixelSize: win.cap }
            }
          }
        }
      }

      // ⁵ gpu
      RqBox {
        width: parent.width
        num: "⁵"; title: "gpu"
        subtitle: win.hub && win.hub.hw.gpu ? win.hub.hw.gpu : ""
        visible: !!(win.hub && win.hub.sys && win.hub.sys.gpu.busy !== null)
        aside: win.hub && win.hub.sys ? win.hub.sys.gpu.busy + " %" + (win.hub.sys.gpu.temp ? " · " + Math.round(win.hub.sys.gpu.temp) + "°" : "")
          + " · VRAM " + go(win.hub.sys.gpu.vram_used) : ""
        RqChartFrame {
          hub: win.hub; yTop: "100"; yMid: ""; yBottom: "0"
          plotHeight: Style.space(76)
          RqGraph {
            width: parent.width; height: parent.height
            values: win.hub ? win.hub.series("gpu", cols) : []
            MouseArea { anchors.fill: parent; hoverEnabled: true; onExited: win.leaveTip(parent); onPositionChanged: function(mouse) { win.graphTip(parent, mouse.x, "gpu") } }
            marks: win.marksFor(win.hub ? win.hub.seriesTimes("gpu", cols) : [])
            maxValue: 100
            tint: win.hub ? win.hub.cGpu : "white"
          }
        }
      }
    }

    // ── colonne de droite : processus + analyse avec Claude ──
    Item {
      id: right
      x: left.x + left.width + Style.space(14)
      y: left.y
      width: card.width - x - Style.space(18)
      height: card.height - y - Style.space(40)

      // filtres rapides (le cœur du PC, épinglé, n'est jamais filtré)
      Row {
        id: chipsRow
        width: parent.width; height: win.rowH
        spacing: Style.space(8)
        Repeater {
          model: [{ k: "tout", t: win.tx("tout", "all") }, { k: "sessions", t: win.tx("sessions Claude", "Claude sessions") }, { k: "applis", t: win.tx("applis", "apps") },
                  { k: "calmes", t: win.tx("calmes > 1 h", "idle > 1 h") }, { k: "fuites", t: win.tx("fuites", "leaks") }]
          Rectangle {
            readonly property bool on: !!win.hub && win.hub.filter === modelData.k
            readonly property int n: win.hub ? (win.hub.filterCounts[modelData.k] || 0) : 0
            // sans aucune session Claude, la puce « sessions Claude » n'a pas de sens
            visible: modelData.k !== "sessions" || n > 0 || on
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(20); radius: height / 2
            width: chipText.implicitWidth + Style.space(20)
            color: on ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.18) : "transparent"
            border.color: on ? Commons.Color.accent : Qt.rgba(win.fg.r, win.fg.g, win.fg.b, chipMa.containsMouse ? 0.35 : 0.18)
            opacity: n === 0 && !on ? 0.5 : 1
            RqText { id: chipText; anchors.centerIn: parent; text: modelData.t + "  " + parent.n; color: parent.on ? Commons.Color.accent : win.dim; font.pixelSize: win.cap }
            MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.hub.filter = modelData.k }
          }
        }
      }

      // ⁶ processus
      RqBox {
        id: procBox
        y: chipsRow.height + win.gap
        width: parent.width
        height: parent.height - freeBox.height - chipsRow.height - win.gap * 2
        num: "⁶"; title: win.tx("processus", "processes")
        aside: win.hub && win.hub.info ? win.hub.tableGroups.filter(function(g) { return g.kind !== "personne" && g.kind !== "sep" }).length + win.tx(" groupes · ", " groups · ") + (win.hub.info.procs ? win.hub.info.procs.length : "…") + win.tx(" processus", " processes") : win.tx("lecture…", "reading…")

        // en-têtes de colonnes (clic : trier, second clic : inverser)
        Item {
          id: colHeads
          width: parent.width; height: win.rowH
          Repeater {
            model: win.columns
            RqText {
              readonly property bool sorted: win.hub && modelData.k !== "" && win.hub.sortKey === modelData.k
              x: colHeads.width * modelData.x + (modelData.k === "pct" ? Style.space(10) : 0)
              width: colHeads.width * modelData.w - 6
              text: (sorted ? (win.hub.sortAsc ? "▴ " : "▾ ") : "") + modelData.t
              color: sorted ? Commons.Color.accent : hma.containsMouse && modelData.k !== "" ? win.fg : win.dim
              font.pixelSize: win.cap
              font.underline: hma.containsMouse && modelData.k !== ""
              horizontalAlignment: modelData.r ? Text.AlignRight : Text.AlignLeft
              MouseArea {
                id: hma
                anchors.fill: parent
                enabled: modelData.k !== ""
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: win.hub.sortBy(modelData.k)
              }
            }
          }
        }

        ListView {
          id: list
          width: parent.width
          height: procBox.height - procBox.headerHeight - win.rowH * 2 - Style.space(20)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: rowsModel
          cacheBuffer: 400
          onContentYChanged: win.hideTip()

          delegate: Column {
            id: grp
            width: list.width
            readonly property var g: (win.hub && win.hub.groupById[model.gid]) || ({ id: model.gid, name: "", kind: "app", procs: 0, cpu: 0, ram: 0, zram: 0, idle: 0, poids_mort: 0, roots: [], twins: [], protected: false, paused: false, scratch: 0 })
            readonly property bool isClaude: g.kind === "claude"
            readonly property bool isPersonne: g.kind === "personne"
            readonly property bool isSep: g.kind === "sep"

            // séparateur entre le cœur du PC et les processus
            Item {
              visible: grp.isSep
              width: parent.width; height: Style.space(12)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 1
                color: Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.22)
              }
            }
            readonly property bool open: !!(win.hub && win.hub.expanded[g.id])
            readonly property var ps: win.hub ? (win.hub.procsByGroup[g.id] || []) : []
            readonly property real mem: g.ram + g.zram

            Rectangle {
              id: grow
              visible: !grp.isSep
              width: parent.width; height: win.rowH
              readonly property bool hot: rowHover.hovered || (!!win.hub && win.hub.armed !== "" && win.hub.armed.indexOf(grp.g.id) >= 0)
              color: hot ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.06) : grp.isPersonne ? Qt.rgba(0.88, 0.69, 0.41, 0.035) : "transparent"
              radius: 4
              HoverHandler { id: rowHover }
              MouseArea {
                id: gma
                anchors.fill: parent; hoverEnabled: true
                cursorShape: grp.isPersonne ? Qt.ArrowCursor : Qt.PointingHandCursor
                onClicked: { win.hideTip(); if (!grp.isPersonne) win.hub.toggleExpanded(grp.g.id) }
                onContainsMouseChanged: containsMouse ? win.queueTip(grp.g.name,
                  (grp.g.leak ? win.tx("Fuite probable : sa mémoire monte de ", "Probable leak: its memory grows by ") + win.hub.go(grp.g.leak) + win.tx(" par heure depuis 30 min.\n\n", " per hour over the last 30 min.\n\n") : "") + (grp.g.desc || ""), parent) : win.leaveTip(parent)
              }
              Row {
                x: 0; width: parent.width * win.col("name").w - 6
                height: parent.height
                spacing: Style.space(6)
                clip: true
                RqText {
                  height: parent.height
                  text: grp.isPersonne ? "■" : grp.open ? "▾" : "▸"
                  color: grp.isPersonne ? (grp.g.id === "personne:tmp" ? win.hub.cFiles : win.hub.cKernel) : win.dim
                }
                // pastille : bleu = session Claude, vert = appli
                Rectangle {
                  visible: !grp.isPersonne && grp.g.kind !== "petits"
                  anchors.verticalCenter: parent.verticalCenter
                  width: 6; height: 6; radius: 3
                  color: grp.isClaude ? win.hub.cSessions : win.hub.cApps
                }
                RqText {
                  id: gname
                  height: parent.height
                  width: Math.min(implicitWidth, parent.width * 0.7)
                  text: grp.g.name
                  color: grp.g.leak ? win.hub.cFiles : grp.g.twins && grp.g.twins.length ? Commons.Color.urgent
                    : grp.isClaude ? win.hub.cSessions : grp.isPersonne ? (grp.g.id === "personne:tmp" ? win.hub.cFiles : win.hub.cKernel)
                    : grp.g.kind === "petits" ? win.dim : win.fg
                }
                RqText {
                  height: parent.height
                  text: grp.g.leak ? "↗ +" + win.hub.go(grp.g.leak) + "/h"
                    : grp.g.twins && grp.g.twins.length ? win.tx("×2 avec ", "×2 with ") + grp.g.twins[0]
                    : grp.isClaude ? (grp.g.space || "") : ""
                  color: grp.g.leak ? win.hub.cFiles : grp.g.twins && grp.g.twins.length ? Commons.Color.urgent : win.dim
                  font.pixelSize: win.cap
                }
              }
              RqText { x: win.cx("procs", parent); width: win.cw("procs", parent); horizontalAlignment: Text.AlignRight; text: grp.isPersonne ? "" : "×" + grp.g.procs; color: win.dim }
              RqText {
                x: win.cx("cpu", parent); width: win.cw("cpu", parent); horizontalAlignment: Text.AlignRight
                text: grp.isPersonne ? "" : win.hub.pctTxt(grp.g.cpu); color: grp.g.cpu > 25 ? Commons.Color.urgent : grp.g.cpu > 2 ? win.fg : win.dim
              }
              RqText { x: win.cx("ram", parent); width: win.cw("ram", parent); horizontalAlignment: Text.AlignRight; text: go(grp.mem) }
              Row {
                x: win.cx("pct", parent) + Style.space(10); width: win.cw("pct", parent) - Style.space(10)
                height: parent.height
                spacing: Style.space(6)
                RqDots {
                  anchors.verticalCenter: parent.verticalCenter
                  count: 10
                  frac: grp.mem / win.used / 0.2
                  tint: grp.isClaude ? win.hub.cSessions : grp.isPersonne ? (grp.g.id === "personne:tmp" ? win.hub.cFiles : win.hub.cKernel) : win.hub.cApps
                }
                RqText { height: parent.height; text: win.share(grp.mem); color: grp.mem / win.used > 0.05 ? win.fg : win.dim }
              }
              RqText {
                x: win.cx("tmp", parent); width: win.cw("tmp", parent); horizontalAlignment: Text.AlignRight
                text: grp.isClaude && grp.g.scratch > 1048576 ? go(grp.g.scratch) : ""
                color: grp.g.scratch > 1073741824 ? Commons.Color.urgent : win.dim
              }
              RqText {
                x: win.cx("idle", parent) + 8; width: win.cw("idle", parent) - 8
                text: grp.isPersonne || grp.g.kind === "petits" ? "" : win.hub.dur(grp.g.idle)
                color: grp.g.idle < 60 ? "#29D398" : grp.g.idle > 3600 ? win.hub.cFiles : win.dim
              }
              RqText {
                x: win.cx("poids", parent); width: win.cw("poids", parent); horizontalAlignment: Text.AlignRight
                text: grp.g.poids_mort >= 0.05 ? win.hub.num(grp.g.poids_mort, 1) : ""
                color: grp.g.poids_mort > 2 ? win.hub.cFiles : win.dim
              }
              // « protégé » / « sans processus » restent visibles ; les actions n'apparaissent qu'au survol
              RqText {
                x: win.cx("", parent); height: parent.height
                visible: !grow.hot && !grp.isClaude && grp.g.protected && grp.g.kind !== "petits"
                text: grp.isPersonne ? win.tx("sans processus", "no process") : win.tx("protégé", "protected")
                color: win.dim; font.pixelSize: win.cap
              }
              Row {
                x: win.cx("", parent)
                height: parent.height
                spacing: Style.space(10)
                visible: grow.hot
                RqAct {
                  visible: grp.isClaude && !!grp.g.terminal; height: parent.height
                  hub: win.hub
                  label: win.tx("voir ↗", "show ↗")
                  onActivated: { win.hub.run(["montrer", String(grp.g.pid)]); win.hub.closeWindow() }
                }
                RqAct {
                  visible: grp.isClaude; height: parent.height
                  hub: win.hub; confirm: true; danger: true
                  key: "g-fermer-" + grp.g.id; label: win.tx("fermer", "close")
                  onActivated: win.hub.run(["fermer", String(grp.g.pid)], grp.g.name + win.tx(" fermée (reprise : claude --resume)", " closed (resume: claude --resume)"))
                }
                RqAct {
                  visible: !grp.isClaude && !grp.g.protected; height: parent.height
                  hub: win.hub
                  label: grp.g.paused ? win.tx("reprendre", "resume") : "pause"
                  onActivated: win.hub.run(["action", grp.g.paused ? "reprendre" : "pause"].concat(grp.g.roots.map(String)))
                }
                RqAct {
                  visible: !grp.isClaude && !grp.g.protected; height: parent.height
                  hub: win.hub; confirm: true; danger: true
                  key: "g-term-" + grp.g.id; label: win.tx("terminer", "terminate")
                  onActivated: win.hub.run(["action", "terminer"].concat(grp.g.roots.map(String)), grp.g.name + win.tx(" terminé", " terminated"))
                }
                RqText { visible: !grp.isClaude && grp.g.protected && grp.g.kind !== "petits"; height: parent.height; text: grp.isPersonne ? win.tx("sans processus", "no process") : win.tx("protégé", "protected"); color: win.dim; font.pixelSize: win.cap }
              }
            }

            // processus du groupe, une fois déplié
            Repeater {
              model: grp.open ? grp.ps.slice(0, 60) : []
              Rectangle {
                id: prow
                readonly property var p: modelData
                width: grp.width; height: Math.round(win.rowH * 0.9)
                readonly property bool hot: procHover.hovered || (!!win.hub && win.hub.armed !== "" && win.hub.armed.indexOf(String(p.pid)) >= 0)
                color: hot ? Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.04) : "transparent"
                HoverHandler { id: procHover }
                MouseArea {
                  id: pma
                  anchors.fill: parent; hoverEnabled: true
                  onContainsMouseChanged: {
                    if (!containsMouse) { win.leaveTip(prow); return }
                    var d = win.hub.info && win.hub.info.descs ? win.hub.info.descs[prow.p.label] : ""
                    win.queueTip(prow.p.label + " · pid " + prow.p.pid, (d ? d + "\n\n" : "") + prow.p.cmd, prow)
                  }
                }
                RqText {
                  x: Style.space(18); width: parent.width * win.col("name").w - Style.space(24)
                  text: p.pid + "  " + p.label + (p.label !== p.name ? " (" + p.name + ")" : "")
                  color: p.state === "T" ? win.hub.cFiles : win.dim
                  font.pixelSize: win.cap
                }
                RqText {
                  x: win.cx("cpu", parent); width: win.cw("cpu", parent); horizontalAlignment: Text.AlignRight
                  text: win.hub.pctTxt(p.cpu); color: win.dim; font.pixelSize: win.cap
                }
                RqText {
                  x: win.cx("ram", parent); width: win.cw("ram", parent); horizontalAlignment: Text.AlignRight
                  text: go(p.ram + p.swap); color: win.dim; font.pixelSize: win.cap
                }
                RqText {
                  x: win.cx("pct", parent); width: win.cw("pct", parent); horizontalAlignment: Text.AlignRight
                  text: win.share(p.ram + p.swap); color: win.dim; font.pixelSize: win.cap
                }
                RqText {
                  x: win.cx("idle", parent) + 8; width: parent.width * 0.14
                  text: p.state === "T" ? win.tx("en pause", "paused") : (p.nice > 0 ? win.tx("priorité basse", "low priority") : "")
                  color: win.hub.cFiles; font.pixelSize: win.cap
                }
                Row {
                  x: win.cx("", parent)
                  height: parent.height
                  spacing: Style.space(8)
                  visible: !p.protected && prow.hot
                  RqAct {
                    height: parent.height; hub: win.hub
                    label: p.state === "T" ? win.tx("reprendre", "resume") : "pause"
                    onActivated: win.hub.run(["action", p.state === "T" ? "reprendre" : "pause", String(p.pid)])
                  }
                  RqAct {
                    height: parent.height; hub: win.hub
                    label: p.nice > 0 ? "prio ↑" : "prio ↓"
                    onActivated: win.hub.run(["action", p.nice > 0 ? "normal" : "priorite", String(p.pid)])
                  }
                  RqAct {
                    height: parent.height; hub: win.hub; confirm: true; danger: true
                    key: "p-term-" + p.pid; label: win.tx("terminer", "terminate")
                    onActivated: win.hub.run(["action", "terminer", String(p.pid)])
                  }
                  RqAct {
                    height: parent.height; hub: win.hub; confirm: true; danger: true
                    key: "p-kill-" + p.pid; label: win.tx("tuer", "kill")
                    onActivated: win.hub.run(["action", "tuer", String(p.pid)])
                  }
                }
                RqText {
                  x: win.cx("", parent); visible: p.protected; height: parent.height
                  text: win.tx("protégé", "protected"); color: win.dim; font.pixelSize: win.cap
                }
              }
            }
          }
        }

        // total fixe des lignes affichées
        Rectangle {
          width: parent.width; height: 1
          color: Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.12)
        }
        Item {
          id: totals
          width: parent.width; height: win.rowH + Style.space(4)
          readonly property var rows: !win.hub ? [] : win.hub.tableGroups.filter(function(g) {
            return g.kind !== "sep" && !(g.kind === "petits" && win.hub.expanded["petits"]) })
          readonly property real mem: rows.reduce(function(s, g) { return s + g.ram + g.zram }, 0)
          readonly property real cpu: rows.reduce(function(s, g) { return s + g.cpu }, 0)
          readonly property real tmp: rows.reduce(function(s, g) { return s + (g.scratch || 0) }, 0)
          readonly property int procs: rows.reduce(function(s, g) { return s + g.procs }, 0)
          readonly property int groups: rows.reduce(function(s, g) {
            return s + (g.kind === "personne" ? 0 : g.kind === "petits" ? parseInt(g.name) || 0 : 1) }, 0)
          RqText {
            x: 0; width: parent.width * win.col("name").w - 6; height: parent.height
            font.bold: true
            text: "total · " + totals.groups + win.tx(" groupes", " groups") + (totals.rows.length > totals.groups ? win.tx(" + sans processus", " + no process") : "") + (win.hub && win.hub.search !== "" ? win.tx(" trouvés", " found") : "")
          }
          RqText { x: win.cx("procs", parent); width: win.cw("procs", parent); height: parent.height; horizontalAlignment: Text.AlignRight; font.bold: true; text: "×" + totals.procs }
          RqText { x: win.cx("cpu", parent); width: win.cw("cpu", parent); height: parent.height; horizontalAlignment: Text.AlignRight; font.bold: true; text: win.hub ? win.hub.pctTxt(totals.cpu) : "" }
          RqText { x: win.cx("ram", parent); width: win.cw("ram", parent); height: parent.height; horizontalAlignment: Text.AlignRight; font.bold: true; text: go(totals.mem) }
          RqText { x: win.cx("pct", parent); width: win.cw("pct", parent); height: parent.height; horizontalAlignment: Text.AlignRight; font.bold: true; text: win.share(totals.mem) }
          RqText { x: win.cx("tmp", parent); width: win.cw("tmp", parent); height: parent.height; horizontalAlignment: Text.AlignRight; font.bold: true; text: totals.tmp > 1048576 ? go(totals.tmp) : "" }
          RqText {
            x: win.cx("idle", parent) + 8; width: parent.width - win.cx("idle", parent) - 8; height: parent.height
            color: win.dim; font.pixelSize: win.cap
            text: !win.hub || !win.hub.info ? ""
              : win.hub.search === "" ? win.tx("= toute la RAM utilisée, comme le graphique", "= all the RAM in use, like the chart")
              : win.tx("sur ", "of ") + go(win.used) + win.tx(" utilisés", " used")
          }
        }
      }

      // ⁷ comprendre et libérer : une conversation Claude analyse le relevé
      RqBox {
        id: freeBox
        y: procBox.y + procBox.height + win.gap
        width: parent.width
        num: "⁷"; title: win.hasClaude ? win.tx("comprendre et libérer", "understand and free up") : win.tx("libérer", "free up")
        aside: win.hub && win.hub.sys ? win.tx("dispo ", "available ") + go(win.hub.sys.available) : ""

        Item {
          width: parent.width; height: win.rowH * 2 + Style.space(6)
          Column {
            width: parent.width * (win.hasClaude ? 0.68 : 1)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            RqText {
              width: parent.width
              text: win.hub ? win.hub.suggestion : ""
              color: win.fg
            }
            RqText {
              width: parent.width
              visible: win.hasClaude
              text: win.tx("Claude lit un relevé complet de la machine, t'explique pourquoi la mémoire en est là",
                           "Claude reads a full report of the machine, explains why memory is where it is")
              color: win.dim
              font.pixelSize: win.cap
            }
            RqText {
              width: parent.width
              visible: win.hasClaude
              text: win.tx("et te propose un plan classé par gain et par risque. Il ne touche à rien sans ton accord.",
                           "and suggests a plan ranked by gain and risk. It touches nothing without your consent.")
              color: win.dim; font.pixelSize: win.cap
            }
          }
          Rectangle {
            visible: win.hasClaude
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: analyseLabel.implicitWidth + Style.space(28); height: Style.space(32)
            radius: Style.space(8)
            color: analyseMa.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22)
                                           : Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)
            border.color: Commons.Color.accent
            RqText {
              id: analyseLabel
              anchors.centerIn: parent
              text: win.hub && win.hub.analysing ? win.tx("ouverture…", "opening…") : win.tx("Analyser avec Claude ↗", "Analyze with Claude ↗")
              color: Commons.Color.accent
              font.bold: true
            }
            MouseArea {
              id: analyseMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: win.hub.analyser(win.tx("demandée depuis la fenêtre Ardoise", "requested from the Ardoise window"))
            }
          }
        }
      }
    }

    // ── pied : les raccourcis en touches, le dernier résultat, l'état de la machine ──
    Item {
      x: Style.space(18)
      y: card.height - Style.space(30)
      width: card.width - Style.space(36)
      height: Style.space(20)
      RqText {
        visible: !!win.hub && win.hub.toast !== ""
        width: parent.width * 0.7; height: parent.height
        text: win.hub ? win.hub.toast : ""
        color: Commons.Color.accent; font.pixelSize: win.cap
      }
      Row {
        visible: !win.hub || win.hub.toast === ""
        height: parent.height
        spacing: Style.space(16)
        Repeater {
          model: [{ k: "/", t: win.tx("chercher", "search") }, { k: win.tx("Échap", "Esc"), t: win.tx("fermer", "close") },
                  { k: "", t: win.tx("clic sur un en-tête : trier", "click a header: sort") },
                  { k: "", t: win.tx("clic sur un groupe : ses processus", "click a group: its processes") },
                  { k: "", t: win.tx("survol : ce que c'est", "hover: what it is") }]
          Row {
            height: parent.height
            spacing: Style.space(5)
            Rectangle {
              visible: modelData.k !== ""
              anchors.verticalCenter: parent.verticalCenter
              width: keyText.implicitWidth + Style.space(10); height: Style.space(16); radius: 3
              color: "transparent"; border.color: Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.3)
              RqText { id: keyText; anchors.centerIn: parent; text: modelData.k; color: win.fg; font.pixelSize: win.cap }
            }
            RqText { height: parent.height; text: modelData.t; color: win.dim; font.pixelSize: win.cap }
          }
        }
      }
      RqText {
        anchors.right: parent.right; height: parent.height
        color: win.dim; font.pixelSize: win.cap
        text: !win.hub || !win.hub.sys ? "" :
          win.tx("allumé depuis ", "up ") + win.hub.dur(win.hub.sys.uptime) + win.tx(" · charge ", " · load ") + win.hub.sys.load.map(function(v) { return win.hub.num(v, 2) }).join(" ")
      }
    }

    // ── info-bulle : ce qu'est le groupe ou le processus survolé ──
    Rectangle {
      id: tip
      visible: win.tipShown && win.tipItem !== null
      readonly property point at: visible && win.tipItem ? win.tipItem.mapToItem(card, 0, 0) : Qt.point(0, 0)
      readonly property real rowH: win.tipItem ? win.tipItem.height : 0
      width: Style.space(440)
      height: tipCol.implicitHeight + Style.space(18)
      x: Math.min(card.width - width - Style.space(12), Math.max(Style.space(12), at.x + Style.space(40)))
      y: at.y + rowH + height + Style.space(6) > card.height ? at.y - height - Style.space(4) : at.y + rowH + Style.space(4)
      z: 100
      radius: Style.space(8)
      color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.98)
      border.color: Commons.Color.accent
      border.width: 1
      Column {
        id: tipCol
        x: Style.space(12); y: Style.space(9)
        width: tip.width - Style.space(24)
        spacing: Style.space(4)
        RqText {
          width: parent.width
          text: win.tipTitle
          color: Commons.Color.accent
          font.bold: true
        }
        RqText {
          width: parent.width
          text: win.tipBody
          wrapMode: Text.Wrap
          elide: Text.ElideNone
          maximumLineCount: 14
          color: win.fg
          font.pixelSize: win.cap
        }
      }
    }
  }
}
