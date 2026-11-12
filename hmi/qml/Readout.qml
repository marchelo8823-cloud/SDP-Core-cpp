import QtQuick

// Строка «название — значение»
Item {
    id: r
    property string label: ""
    property string value: ""
    property color tone: Theme.text
    property int px: Theme.px(15)
    height: Theme.px(24)
    Text { text: r.label; color: Theme.sub; font.pixelSize: r.px; anchors.verticalCenter: parent.verticalCenter }
    Text { text: r.value; color: r.tone; font.pixelSize: r.px; font.bold: true; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
           font.family: Theme.mono }
}
