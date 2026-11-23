import QtQuick
import qs.Commons
import qs.Commons as Commons

// Bouton texte. Avec `confirm`, le premier clic l'arme (« sûr ? »), le second lance.
Text {
  id: btn
  property var hub: null
  property string key: ""
  property string label: ""
  property bool confirm: false
  property bool danger: false
  property bool active: true
  signal activated()
  readonly property bool isArmed: hub && hub.armed === key && key !== ""
  readonly property color base: Commons.Color.popups.text

  text: isArmed ? (hub ? hub.t("sûr ?", "sure?") : "sûr ?") : label
  color: !active ? Qt.rgba(base.r, base.g, base.b, 0.25)
       : isArmed ? Commons.Color.urgent
       : ma.containsMouse ? (danger ? Commons.Color.urgent : Commons.Color.accent)
       : Qt.rgba(base.r, base.g, base.b, 0.7)
  font.family: Style.font.family
  font.pixelSize: Style.font.caption
  font.underline: ma.containsMouse && btn.active
  textFormat: Text.PlainText
  verticalAlignment: Text.AlignVCenter

  MouseArea {
    id: ma
    anchors.fill: parent
    anchors.margins: -3
    hoverEnabled: true
    cursorShape: btn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(mouse) {
      mouse.accepted = true
      if (!btn.active) return
      if (btn.confirm && btn.hub) {
        if (btn.hub.armed !== btn.key) { btn.hub.arm(btn.key); return }
        btn.hub.armed = ""
      }
      btn.activated()
    }
  }
}
