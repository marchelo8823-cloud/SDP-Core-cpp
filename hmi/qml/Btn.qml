import QtQuick

Rectangle {
    id: b
    property string text: ""
    property bool active: false
    property bool danger: false
    property bool enabledBtn: true
    property int px: Theme.px(15)
    signal clicked()
    implicitWidth: label.implicitWidth + Theme.px(22)
    implicitHeight: Theme.px(40)
    radius: 6
    opacity: enabledBtn ? 1 : 0.4
    color: active ? Theme.accent : (ma.pressed ? Theme.line : (ma.containsMouse ? Theme.panel2 : "transparent"))
    border.color: danger ? Theme.bad : (active ? Theme.accent : Theme.line)
    border.width: 1
    Text {
        id: label
        anchors.centerIn: parent
        text: b.text
        color: b.active ? (Theme.preset === 3 || Theme.preset === 0 ? "#ffffff" : Theme.bg) : (b.danger ? Theme.bad : Theme.text)
        font.pixelSize: b.px; font.bold: b.active
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: b.enabledBtn; onClicked: b.clicked() }
}
