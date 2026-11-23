import QtQuick
import qs.Commons
import qs.Commons as Commons

// Texte de base : police mono du thème, jamais de texte riche (les lignes de commande
// des processus viennent de l'extérieur et ne doivent pas être interprétées).
Text {
  color: Commons.Color.popups.text
  font.family: Style.font.family
  font.pixelSize: Style.font.bodySmall
  textFormat: Text.PlainText
  elide: Text.ElideRight
  verticalAlignment: Text.AlignVCenter
}
