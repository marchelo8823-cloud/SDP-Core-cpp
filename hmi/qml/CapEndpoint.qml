import QtQuick
import QtQuick.Controls

// Редактор одной линии записи обмена (UDP / TCP-клиент / TCP-сервер / COM). Правит переданный объект ep и сообщает об изменении.
Column {
    id: e
    property var ep: null
    property bool editable: true
    property string label: "Линия"
    signal changed()
    spacing: 6
    readonly property var types: ["udp", "tcpc", "tcps", "serial"]
    readonly property string t: ep ? ep.type : "udp"

    Row { spacing: 8
        Text { anchors.verticalCenter: parent.verticalCenter; width: Theme.px(70); text: e.label; color: Theme.sub; font.pixelSize: Theme.px(13) }
        Seg { width: Theme.px(480); px: Theme.px(12); enabled: e.editable; model: ["UDP", "TCP-клиент", "TCP-сервер", "COM"]
              current: { var i = e.types.indexOf(e.t); return i < 0 ? 0 : i }
              onPicked: (i) => { e.ep.type = e.types[i]; e.changed() } }
    }
    Row { spacing: 8; visible: e.t === "udp"
        Text { anchors.verticalCenter: parent.verticalCenter; text: "слушать"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        TextField { width: Theme.px(140); text: e.ep ? e.ep.bind : ""; enabled: e.editable; color: Theme.text; font.pixelSize: Theme.px(13); background: Rectangle { color: Theme.panel; radius: 5; border.color: Theme.line }
                    onEditingFinished: { e.ep.bind = text; e.changed() } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "порт"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        TextField { width: Theme.px(80); text: e.ep ? String(e.ep.port) : ""; enabled: e.editable; color: Theme.text; font.pixelSize: Theme.px(13); horizontalAlignment: TextInput.AlignRight; background: Rectangle { color: Theme.panel; radius: 5; border.color: Theme.line }
                    onEditingFinished: { e.ep.port = Math.round(Number(text)) || 0; e.changed() } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "группа"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        TextField { width: Theme.px(130); text: e.ep ? e.ep.group : ""; enabled: e.editable; placeholderText: "multicast"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(13); background: Rectangle { color: Theme.panel; radius: 5; border.color: Theme.line }
                    onEditingFinished: { e.ep.group = text; e.changed() } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "слать на"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        TextField { width: Theme.px(160); text: e.ep ? e.ep.dest : ""; enabled: e.editable; placeholderText: "адрес:порт"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(13); background: Rectangle { color: Theme.panel; radius: 5; border.color: Theme.line }
                    onEditingFinished: { e.ep.dest = text; e.changed() } }
    }
    Row { spacing: 8; visible: e.t === "tcpc"
        Text { anchors.verticalCenter: parent.verticalCenter; text: "сервер"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        TextField { width: Theme.px(160); text: e.ep ? e.ep.host : ""; enabled: e.editable; placeholderText: "IP-адрес"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(13); background: Rectangle { color: Theme.panel; radius: 5; border.color: Theme.line }
                    onEditingFinished: { e.ep.host = text; e.changed() } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "порт"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        TextField { width: Theme.px(80); text: e.ep ? String(e.ep.port) : ""; enabled: e.editable; color: Theme.text; font.pixelSize: Theme.px(13); horizontalAlignment: TextInput.AlignRight; background: Rectangle { color: Theme.panel; radius: 5; border.color: Theme.line }
                    onEditingFinished: { e.ep.port = Math.round(Number(text)) || 0; e.changed() } }
    }
    Row { spacing: 8; visible: e.t === "tcps"
        Text { anchors.verticalCenter: parent.verticalCenter; text: "слушать"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        TextField { width: Theme.px(140); text: e.ep ? e.ep.bind : ""; enabled: e.editable; color: Theme.text; font.pixelSize: Theme.px(13); background: Rectangle { color: Theme.panel; radius: 5; border.color: Theme.line }
                    onEditingFinished: { e.ep.bind = text; e.changed() } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "порт"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        TextField { width: Theme.px(80); text: e.ep ? String(e.ep.port) : ""; enabled: e.editable; color: Theme.text; font.pixelSize: Theme.px(13); horizontalAlignment: TextInput.AlignRight; background: Rectangle { color: Theme.panel; radius: 5; border.color: Theme.line }
                    onEditingFinished: { e.ep.port = Math.round(Number(text)) || 0; e.changed() } }
    }
    Row { spacing: 8; visible: e.t === "serial"
        Text { anchors.verticalCenter: parent.verticalCenter; text: "порт"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        TextField { width: Theme.px(230); text: e.ep ? e.ep.device : ""; enabled: e.editable; placeholderText: "COM3 или /dev/cu.usbserial-0001"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(13); background: Rectangle { color: Theme.panel; radius: 5; border.color: Theme.line }
                    onEditingFinished: { e.ep.device = text; e.changed() } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "скорость"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        TextField { width: Theme.px(85); text: e.ep ? String(e.ep.baud) : ""; enabled: e.editable; color: Theme.text; font.pixelSize: Theme.px(13); horizontalAlignment: TextInput.AlignRight; background: Rectangle { color: Theme.panel; radius: 5; border.color: Theme.line }
                    onEditingFinished: { e.ep.baud = Math.round(Number(text)) || 9600; e.changed() } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "чётность"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        Seg { width: Theme.px(150); px: Theme.px(12); enabled: e.editable; model: ["N", "E", "O"]; current: e.ep ? Math.max(0, ["N", "E", "O"].indexOf(e.ep.parity)) : 0
              onPicked: (i) => { e.ep.parity = ["N", "E", "O"][i]; e.changed() } }
        Text { anchors.verticalCenter: parent.verticalCenter; text: "стоп"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        Seg { width: Theme.px(100); px: Theme.px(12); enabled: e.editable; model: ["1", "2"]; current: e.ep && e.ep.stop === 2 ? 1 : 0
              onPicked: (i) => { e.ep.stop = i + 1; e.changed() } }
    }
}
