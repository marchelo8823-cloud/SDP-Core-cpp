import QtQuick

Rectangle {
    id: c
    property string text: ""
    property color tone: Theme.accent
    property bool solid: false
    implicitHeight: Theme.px(30)
    implicitWidth: t.implicitWidth + Theme.px(20)
    radius: height / 2
    color: solid ? tone : "transparent"
    border.color: tone; border.width: 1
    Text { id: t; anchors.centerIn: parent; text: c.text; font.pixelSize: Theme.px(14); font.bold: true
           color: c.solid ? (Theme.preset === 2 ? Theme.bg : "#ffffff") : c.tone }
}
