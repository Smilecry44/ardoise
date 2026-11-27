import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Fiche machine d'Ardoise : matériel, logiciel, état, et une copie en Markdown
// à coller sur un forum. Les lignes viennent de `ardoise machine --json`, déjà
// écrites dans la bonne langue ; l'IP locale reste hors de la copie sauf demande.
PanelWindow {
  id: mw
  property var hub: null
  property var screenRef: null

  screen: screenRef
  visible: hub !== null
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "ardoise-machine"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.68)
  readonly property color line: Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  readonly property int cap: Style.font.caption
  readonly property int fs: Style.font.bodySmall
  readonly property int labelW: Style.space(104)

  function tx(fr, en) { return hub ? hub.t(fr, en) : fr }

  // ── données ──
  property var card: null
  property bool withIp: false
  property string copied: ""          // "" | "all" | libellé de la ligne copiée
  function section(k) {
    if (!card) return []
    for (var i = 0; i < card.sections.length; i++) if (card.sections[i].key === k) return card.sections[i].rows
    return []
  }
  function rowText(r) {
    var v = [r.value, r.res, r.hz, r.inch, r.amount, r.detail].filter(function(x) { return x }).join(" · ")
    return (r.label ? r.label + " : " : "") + v
  }
  function copy(text, what) {
    clip.command = ["wl-copy", "--", text]
    clip.running = true
    copied = what
    copiedTimer.restart()
  }
  function copyAll() { if (card) copy(withIp ? card.text_ip : card.text, "all") }

  Process {
    id: load
    command: mw.hub ? ["python3", mw.hub.cli, "machine", "--json", "--lang", mw.hub.lang] : []
    running: mw.hub !== null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { mw.card = JSON.parse(text) } catch (e) { mw.card = null } }
    }
  }
  Process { id: clip }
  Timer { id: copiedTimer; interval: 1600; onTriggered: mw.copied = "" }

  // voile : un clic en dehors ferme la fiche
  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.35)
    MouseArea { anchors.fill: parent; onClicked: mw.hub.closeMachine() }
  }

  Rectangle {
    id: box
    width: Math.min(parent.width - Style.space(80), Style.space(1000))
    height: Math.min(parent.height - Style.space(80), col.implicitHeight + Style.space(32))
    anchors.centerIn: parent
    radius: Style.space(14)
    color: Qt.rgba(Commons.Color.background.r, Commons.Color.background.g, Commons.Color.background.b, 0.99)
    border.color: Commons.Color.accent
    border.width: Math.max(1, Style.space(2))
    clip: true
    MouseArea { anchors.fill: parent }

    Item {
      anchors.fill: parent
      focus: true
      Component.onCompleted: forceActiveFocus()
      Keys.onEscapePressed: mw.hub.closeMachine()
      Keys.onPressed: function(e) {
        if (e.text === "c") { mw.copyAll(); e.accepted = true }
        else if (e.text === "i") { mw.withIp = !mw.withIp; e.accepted = true }
      }
    }

    Column {
      id: col
      x: Style.space(20); y: Style.space(16)
      width: box.width - Style.space(40)
      spacing: Style.space(14)

      // ── en-tête : titre, depuis quand, IP, copier, fermer ──
      Item {
        width: parent.width
        height: Math.max(head.implicitHeight, actions.implicitHeight)
        Column {
          id: head
          spacing: Style.space(6)
          Row {
            spacing: Style.space(14)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: mw.tx("MACHINE", "MACHINE")
              color: mw.fg
              font.family: Style.font.family; font.pixelSize: Style.font.display; font.bold: true; font.letterSpacing: 3
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              visible: !!mw.card
              height: Style.space(20); radius: height / 2
              width: upText.implicitWidth + Style.space(18)
              color: Qt.rgba(mw.hub.cApps.r, mw.hub.cApps.g, mw.hub.cApps.b, 0.14)
              RqText { id: upText; anchors.centerIn: parent; text: "● " + mw.tx("allumée depuis ", "up for ") + (mw.card ? mw.card.uptime : ""); color: mw.hub.cApps; font.pixelSize: mw.cap }
            }
          }
          RqText {
            width: head.parent.width - actions.width - Style.space(20)
            text: mw.card ? mw.card.subtitle : mw.tx("lecture de la machine…", "reading the machine…")
            color: mw.dim; font.pixelSize: mw.cap
          }
        }
        Row {
          id: actions
          anchors.right: parent.right; anchors.top: parent.top
          spacing: Style.space(10)
          // interrupteur : l'IP locale dans la copie
          Rectangle {
            height: Style.space(28); radius: Style.space(5)
            width: ipRow.implicitWidth + Style.space(20)
            color: ipMa.containsMouse ? Qt.rgba(mw.fg.r, mw.fg.g, mw.fg.b, 0.06) : "transparent"
            border.color: Qt.rgba(mw.fg.r, mw.fg.g, mw.fg.b, 0.16)
            Row {
              id: ipRow
              anchors.centerIn: parent
              spacing: Style.space(8)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(24); height: Style.space(13); radius: height / 2
                color: mw.withIp ? Commons.Color.accent : Qt.rgba(mw.fg.r, mw.fg.g, mw.fg.b, 0.25)
                Rectangle {
                  width: parent.height - 4; height: width; radius: width / 2
                  y: 2; x: mw.withIp ? parent.width - width - 2 : 2
                  color: mw.fg
                  Behavior on x { NumberAnimation { duration: 120 } }
                }
              }
              RqText { anchors.verticalCenter: parent.verticalCenter; text: mw.tx("IP dans la copie", "IP in the copy"); color: mw.dim; font.pixelSize: mw.cap }
            }
            MouseArea { id: ipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mw.withIp = !mw.withIp }
          }
          Rectangle {
            height: Style.space(28); radius: Style.space(5)
            width: copyText.implicitWidth + Style.space(28)
            color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, copyMa.containsMouse ? 0.22 : 0.10)
            border.color: Commons.Color.accent
            opacity: mw.card ? 1 : 0.4
            RqText {
              id: copyText; anchors.centerIn: parent
              text: mw.copied === "all" ? mw.tx("copié ✓", "copied ✓") : mw.tx("copier la fiche", "copy the card")
              color: Commons.Color.accent; font.bold: true; font.pixelSize: mw.cap
            }
            MouseArea { id: copyMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mw.copyAll() }
          }
          RqText {
            height: Style.space(28)
            text: "×"; font.pixelSize: Style.font.body; color: closeMa.containsMouse ? Commons.Color.accent : mw.dim
            MouseArea { id: closeMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: mw.hub.closeMachine() }
          }
        }
      }

      // ── corps : matériel à gauche ; logiciel et état à droite ──
      Row {
        id: bodyRow
        width: parent.width
        spacing: Style.space(14)
        readonly property real leftW: Math.round((width - spacing) * 0.59)

        RqBox {
          width: bodyRow.leftW
          height: Math.max(implicitHeight, rightCol.height)
          num: "¹"; title: mw.tx("matériel", "hardware")
          Item { width: 1; height: Style.space(6) }
          Repeater { model: mw.section("hw"); delegate: rowDelegate }
          Item { width: parent.width; height: Style.space(13); Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 1; color: mw.line } }
          Repeater { model: mw.section("hw2"); delegate: rowDelegate }
          Item { width: 1; height: Style.space(4) }
        }

        Column {
          id: rightCol
          width: bodyRow.width - bodyRow.leftW - bodyRow.spacing
          spacing: Style.space(14)
          RqBox {
            width: parent.width
            num: "²"; title: mw.tx("logiciel", "software")
            Item { width: 1; height: Style.space(6) }
            Repeater { model: mw.section("sw"); delegate: rowDelegate }
            Item { width: 1; height: Style.space(4) }
          }
          RqBox {
            width: parent.width
            num: "³"; title: mw.tx("état", "status")
            Item { width: 1; height: Style.space(6) }
            Repeater { model: mw.section("state"); delegate: rowDelegate }
            RqText {
              width: parent.width
              topPadding: Style.space(4)
              wrapMode: Text.WordWrap; elide: Text.ElideNone
              text: mw.withIp ? mw.tx("L'IP sera dans la copie.", "The IP will be in the copy.")
                              : mw.tx("IP masquée dans la copie, pour la coller sur un forum.", "IP left out of the copy, to paste it on a forum.")
              color: mw.withIp ? mw.hub.cFiles : mw.dim; font.pixelSize: mw.cap
            }
            Item { width: 1; height: Style.space(4) }
          }
        }
      }

      RqText {
        visible: !!mw.card && !mw.card.has_fastfetch
        width: parent.width
        text: mw.tx("Sans fastfetch, la fiche se limite à ce qu'Ardoise lit lui-même (sudo pacman -S fastfetch).",
                    "Without fastfetch, the card only shows what Ardoise reads itself (sudo pacman -S fastfetch).")
        color: mw.hub.cFiles; font.pixelSize: mw.cap
      }

      // ── pied : raccourcis ──
      Item {
        width: parent.width; height: Style.space(20)
        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(16)
          Repeater {
            model: [{ k: "c", t: mw.tx("copier", "copy") }, { k: "i", t: "IP" }, { k: mw.tx("Échap", "Esc"), t: mw.tx("fermer", "close") }]
            Row {
              spacing: Style.space(6)
              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: kText.implicitWidth + Style.space(10); height: kText.implicitHeight + Style.space(2); radius: Style.space(3)
                color: "transparent"; border.color: Qt.rgba(mw.fg.r, mw.fg.g, mw.fg.b, 0.25)
                RqText { id: kText; anchors.centerIn: parent; text: modelData.k; font.pixelSize: mw.cap }
              }
              RqText { anchors.verticalCenter: parent.verticalCenter; text: modelData.t; color: mw.dim; font.pixelSize: mw.cap }
            }
          }
          RqText { anchors.verticalCenter: parent.verticalCenter; text: mw.tx("clic sur une ligne : la copier seule", "click a line: copy it alone"); color: mw.dim; font.pixelSize: mw.cap }
        }
        RqText {
          anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
          text: mw.card && mw.card.has_fastfetch ? mw.tx("lu par fastfetch et /proc", "read by fastfetch and /proc") : mw.tx("lu dans /proc et /sys", "read from /proc and /sys")
          color: mw.dim; font.pixelSize: mw.cap
        }
      }
    }
  }

  // ── une ligne de la fiche : libellé, valeur (barre ou colonnes), détail en dessous ──
  Component {
    id: rowDelegate
    Item {
      id: r
      readonly property var d: modelData
      readonly property bool isCopied: mw.copied !== "" && mw.copied === mw.rowText(d)
      width: parent ? parent.width : 0
      height: rc.implicitHeight + Style.space(7)

      Rectangle {
        anchors.fill: parent; anchors.leftMargin: -Style.space(4); anchors.rightMargin: -Style.space(4)
        radius: Style.space(4)
        color: rMa.containsMouse ? Qt.rgba(mw.fg.r, mw.fg.g, mw.fg.b, 0.05) : "transparent"
      }
      RqText {
        width: mw.labelW - Style.space(8)
        text: r.isCopied ? mw.tx("copié ✓", "copied ✓") : r.d.label
        color: r.isCopied ? Commons.Color.accent : mw.dim
        font.pixelSize: mw.fs
      }
      Column {
        id: rc
        x: mw.labelW
        width: r.width - mw.labelW
        spacing: Style.space(2)
        Row {
          spacing: Style.space(10)
          RqText {
            visible: r.d.value !== ""
            // largeur fixe pour aligner jauges et colonnes d'une ligne à l'autre
            width: r.d.res ? Style.space(84) : r.d.bar !== undefined ? Style.space(150) : Math.min(implicitWidth, rc.width)
            text: r.d.value
            font.pixelSize: mw.fs
            color: r.d.value === mw.tx("sans nom", "unnamed") ? mw.dim : mw.fg
          }
          // écrans : résolution, fréquence, taille en colonnes
          RqText { visible: !!r.d.res; width: Style.space(96); text: r.d.res || ""; font.pixelSize: mw.fs }
          RqText { visible: !!r.d.res; width: Style.space(62); text: r.d.hz || ""; font.pixelSize: mw.fs }
          RqText { visible: !!r.d.res; text: r.d.inch || ""; color: mw.dim; font.pixelSize: mw.fs }
          // mémoire et disques : la jauge à points
          RqDots {
            visible: r.d.bar !== undefined
            anchors.verticalCenter: parent.verticalCenter
            count: 24
            frac: r.d.bar || 0
            tint: r.d.kind === "mem" ? mw.hub.cSessions : r.d.bar > 0.9 ? mw.hub.warn : mw.hub.cApps
          }
          RqText { visible: !!r.d.amount; text: r.d.amount || ""; font.pixelSize: mw.fs }
          RqText { visible: !!r.d.pct; text: r.d.pct || ""; color: mw.dim; font.pixelSize: mw.fs }
          RqText { visible: !!r.d.inline && r.d.detail !== ""; text: "· " + r.d.detail; color: mw.dim; font.pixelSize: mw.fs }
        }
        RqText {
          visible: r.d.detail !== "" && !r.d.inline
          width: rc.width
          text: r.d.detail
          color: r.d.value === "" ? mw.fg : mw.dim
          font.pixelSize: r.d.value === "" ? mw.fs : mw.cap
        }
      }
      MouseArea {
        id: rMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { var t = mw.rowText(r.d); mw.copy(t, t) }
      }
    }
  }
}
