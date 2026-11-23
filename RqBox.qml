import QtQuick
import qs.Commons
import qs.Commons as Commons

// Boîte en verre avec un titre numéroté (¹cpu, ²mem…), comme Boxtop.
Rectangle {
  id: box
  property string num: ""
  property string title: ""
  property string aside: ""
  property string subtitle: ""   // le matériel, en petit après le titre
  property color asideColor: Qt.rgba(fg.r, fg.g, fg.b, 0.68)
  default property alias body: inner.data
  readonly property alias bodyWidth: inner.width
  readonly property real headerHeight: Style.space(24)
  readonly property color fg: Commons.Color.popups.text

  implicitHeight: inner.implicitHeight + Style.space(32)
  radius: Style.space(9)
  color: Qt.rgba(fg.r, fg.g, fg.b, 0.05)
  border.color: Qt.rgba(fg.r, fg.g, fg.b, 0.10)
  border.width: 1

  Text {
    id: titleText
    x: Style.space(10); y: Style.space(6)
    textFormat: Text.StyledText
    text: "<font color='" + Commons.Color.urgent + "'>" + box.num + "</font>" + box.title
    color: Commons.Color.accent
    font.family: Style.font.family; font.pixelSize: Style.font.bodySmall; font.bold: true
  }
  Text {
    x: titleText.x + titleText.implicitWidth + Style.space(8); y: Style.space(6)
    width: Math.max(0, box.width - x - asideText.implicitWidth - Style.space(22))
    visible: box.subtitle !== ""
    text: box.subtitle
    color: Qt.rgba(box.fg.r, box.fg.g, box.fg.b, 0.6)
    textFormat: Text.PlainText
    elide: Text.ElideRight
    font.family: Style.font.family; font.pixelSize: Style.font.caption
    height: titleText.height
    verticalAlignment: Text.AlignVCenter
  }
  Text {
    id: asideText
    anchors.right: parent.right; anchors.rightMargin: Style.space(10); y: Style.space(6)
    text: box.aside; color: box.asideColor
    textFormat: Text.PlainText
    font.family: Style.font.family; font.pixelSize: Style.font.bodySmall
  }
  Column {
    id: inner
    x: Style.space(10); y: Style.space(24)
    width: box.width - Style.space(20)
    spacing: 0
  }
}
