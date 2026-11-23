import QtQuick
import qs.Commons
import qs.Commons as Commons

// Cadre d'une courbe : l'échelle à gauche (haut, milieu, bas) et les heures en bas,
// selon la plage choisie (5 min, 1 h, 24 h). La courbe se place dans `content`.
Item {
  id: f
  property var hub: null
  property string yTop: ""
  property string yMid: ""
  property string yBottom: "0"
  property real plotHeight: 60
  default property alias content: plot.data
  readonly property int axisW: Style.space(36)
  readonly property int axisH: Math.round(Style.font.caption * 1.4)
  readonly property color fg: Commons.Color.popups.text
  readonly property color dim: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property var times: !hub ? ["", "", ""]
    : hub.range === "24h" ? ["−24 h", "−12 h", hub.t("maintenant", "now")]
    : hub.range === "1h" ? ["−1 h", "−30 min", hub.t("maintenant", "now")]
    : ["−5 min", "−2 min 30", hub.t("maintenant", "now")]

  width: parent ? parent.width : 0
  implicitHeight: plotHeight + axisH

  Item {
    width: f.axisW - Style.space(5); height: f.plotHeight
    Repeater {
      model: [{ t: f.yTop, y: 0 }, { t: f.yMid, y: 0.5 }, { t: f.yBottom, y: 1 }]
      Text {
        anchors.right: parent.right
        y: Math.max(0, Math.min(parent.height - height, modelData.y * parent.height - height / 2))
        text: modelData.t
        color: f.dim
        font.family: Style.font.family; font.pixelSize: Math.max(8, Style.font.caption - 1)
        textFormat: Text.PlainText
      }
    }
  }
  Item {
    id: plot
    x: f.axisW
    width: f.width - f.axisW
    height: f.plotHeight
  }
  Item {
    x: f.axisW; y: f.plotHeight + 1
    width: f.width - f.axisW; height: f.axisH
    Repeater {
      model: f.times
      Text {
        x: index === 0 ? 0 : index === 1 ? (parent.width - width) / 2 : parent.width - width
        text: modelData
        color: f.dim
        font.family: Style.font.family; font.pixelSize: Math.max(8, Style.font.caption - 1)
        textFormat: Text.PlainText
      }
    }
  }
}
