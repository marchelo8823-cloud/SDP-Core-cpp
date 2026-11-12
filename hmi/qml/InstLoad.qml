import QtQuick

// Прибор «Загрузка движителей»: вертикальные шкалы упора каждого движителя в процентах от максимума.
Item {
    id: w
    Text { x: Theme.px(10); y: Theme.px(6); text: "Загрузка движителей, %"; color: Theme.sub; font.pixelSize: Theme.px(13) }
    Row {
        id: row
        x: Theme.px(10); y: Theme.px(26); width: parent.width - Theme.px(20); height: parent.height - Theme.px(32)
        spacing: Theme.px(6)
        Repeater {
            model: backend.thrusters
            Item {
                required property var modelData
                readonly property real load: Math.min(1, Math.abs(modelData.pct || 0) / 100)
                width: Math.min(Theme.px(54), (row.width - row.spacing * Math.max(0, backend.thrusters.length - 1)) / Math.max(1, backend.thrusters.length)); height: row.height
                Text { id: pc; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: modelData.enabled ? Math.round(Math.abs(modelData.pct || 0)) : "—"; color: Theme.text; font.pixelSize: Theme.px(13); font.family: Theme.mono }
                Rectangle {
                    x: parent.width * 0.2; y: pc.height + 2; width: parent.width * 0.6; height: parent.height - pc.height - nm.height - 4
                    color: Theme.panel2; border.color: Theme.line; radius: 3
                    Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 } height: (parent.height - 2) * (modelData.enabled ? parent.parent.load : 0); radius: 2
                                color: !modelData.enabled ? Theme.sub : parent.parent.load > 0.9 ? Theme.bad : parent.parent.load > 0.7 ? Theme.warn : Theme.accent }
                }
                Text { id: nm; anchors.bottom: parent.bottom; width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: modelData.id; color: Theme.sub; font.pixelSize: Theme.px(11) }
            }
        }
    }
}
