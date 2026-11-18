// Плитка движителя. Шкала угла у поворотного: деления через 30°, подписи 000/090/180/270 (0° — упор к носу),
// задание — полый треугольник на ободе, факт — стрелка. У туннельного — стрелка на борт (ЛБ/ПрБ),
// у неповоротного — вперёд/назад. Полоса упора горизонтальная −100…+100 % с нулём посередине:
// факт — заливка, задание — риска. Числа справа, подписи короткие, чтобы ничего не обрезалось.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

Rectangle {
    id: tile
    property var t: ({})
    readonly property bool az: t.azimuth === true
    readonly property bool tunnel: t.type === "туннельный"
    readonly property real cmd: t.cmdPct || 0
    readonly property real act: t.fb ? (t.fbPct || 0) : cmd
    readonly property bool off: t.failed || !t.enabled || !t.taken
    readonly property bool lag: t.fb && Math.abs(cmd - act) > 20          // факт отстаёт от задания
    color: Theme.panel2
    radius: 3
    border.color: t.failed ? Theme.alarm : (t.taken ? Theme.line : Theme.panel2)
    border.width: t.failed ? 2 : 1
    implicitHeight: 196

    component Row2: RowLayout {     // строка «подпись … число»: число справа, подпись сокращается, а не число
        property alias label: l.text
        property alias value: v.text
        property alias valueColor: v.color
        Layout.fillWidth: true; spacing: 4
        Label { id: l; color: Theme.dim; font.pixelSize: Theme.fsSmall; Layout.fillWidth: true; elide: Text.ElideRight }
        Label { id: v; color: Theme.text; font.pixelSize: Theme.fs; font.family: Theme.mono; horizontalAlignment: Text.AlignRight }
    }

    // состояние: текст и цвет плашки
    readonly property var st: t.failed ? ["ОТКАЗ", Theme.alarm, Theme.bg]
                             : !t.enabled ? ["вне работы", Theme.line, Theme.dim]
                             : t.taken ? ["в управлении", Qt.darker(Theme.ok, 1.6), Theme.text]
                             : ["не взят", Theme.line, Theme.dim]

    Item {
        anchors.fill: parent; anchors.margins: 10

        // ── заголовок ──
        Label { id: idl; text: t.id || ""; color: Theme.text; font.bold: true; font.pixelSize: 17; font.family: Theme.mono }
        Label {
            anchors.left: idl.right; anchors.leftMargin: 8; anchors.baseline: idl.baseline
            anchors.right: pill.left; anchors.rightMargin: 6; elide: Text.ElideRight
            text: t.type || ""; color: Theme.dim; font.pixelSize: Theme.fsSmall
        }
        Rectangle {
            id: pill
            anchors.right: parent.right; anchors.verticalCenter: idl.verticalCenter
            radius: 2; width: stl.implicitWidth + 12; height: stl.implicitHeight + 4; color: tile.st[1]
            Label { id: stl; anchors.centerIn: parent; text: tile.st[0]; color: tile.st[2]; font.pixelSize: 12; font.bold: true }
        }

        // ── шкала угла / направления ──
        Canvas {
            id: dial
            anchors.left: parent.left; anchors.leftMargin: -6; anchors.top: idl.bottom; anchors.topMargin: 2
            width: 146; height: 136
            onPaint: {
                const g = getContext("2d"); g.reset()
                const c = width / 2, cy = height / 2, r = width / 2 - 33
                const pol = function (rr, deg) { const a = deg * Math.PI / 180; return [c + Math.sin(a) * rr, cy - Math.cos(a) * rr] }
                g.fillStyle = Theme.panel; g.beginPath(); g.arc(c, cy, r, 0, 2 * Math.PI); g.fill()
                g.strokeStyle = Theme.line; g.lineWidth = 2; g.beginPath(); g.arc(c, cy, r, 0, 2 * Math.PI); g.stroke()
                for (let b = 0; b < 360; b += 30) {
                    const p1 = pol(r, b), p2 = pol(r - (b % 90 ? 5 : 9), b)
                    g.strokeStyle = Theme.dim; g.lineWidth = b % 90 ? 1 : 2
                    g.beginPath(); g.moveTo(p1[0], p1[1]); g.lineTo(p2[0], p2[1]); g.stroke()
                }
                g.fillStyle = Theme.dim; g.textAlign = "center"; g.textBaseline = "middle"
                const lab = tile.az ? ["000", "090", "180", "270"] : tile.tunnel ? ["нос", "ПрБ", "", "ЛБ"] : ["вперёд", "", "назад", ""]
                g.font = Theme.cfont(tile.az ? 11 : 10, false, tile.az)
                for (let i = 0; i < 4; ++i) if (lab[i]) { const p = pol(r + 22, i * 90); g.fillText(lab[i], p[0], p[1]) }
                const live = !tile.off
                const arrow = function (deg, len, col, w) {
                    const e = pol(len, deg)
                    g.strokeStyle = col; g.fillStyle = col; g.lineWidth = w
                    g.beginPath(); g.moveTo(c, cy); g.lineTo(e[0], e[1]); g.stroke()
                    const a = deg * Math.PI / 180
                    g.beginPath(); g.moveTo(e[0] + Math.sin(a) * 6, e[1] - Math.cos(a) * 6)
                    g.lineTo(e[0] + Math.sin(a + 2.4) * 8, e[1] - Math.cos(a + 2.4) * 8)
                    g.lineTo(e[0] + Math.sin(a - 2.4) * 8, e[1] - Math.cos(a - 2.4) * 8); g.closePath(); g.fill()
                }
                if (tile.az) {
                    // задание — полый треугольник на ободе
                    const ca = t.cmdAng || 0, tip = pol(r - 1, ca), l = pol(r + 11, ca - 10), rr = pol(r + 11, ca + 10)
                    g.beginPath(); g.moveTo(tip[0], tip[1]); g.lineTo(l[0], l[1]); g.lineTo(rr[0], rr[1]); g.closePath()
                    g.fillStyle = Theme.panel2; g.fill(); g.strokeStyle = Theme.accent; g.lineWidth = 2; g.stroke()
                    if (t.fb) arrow(t.fbAng || 0, r - 14, live ? Theme.fb : Theme.dim, 4)
                } else if (Math.abs(tile.act) > 1) {
                    const deg = tile.tunnel ? (tile.act > 0 ? 90 : 270) : (tile.act > 0 ? 0 : 180)
                    arrow(deg, 10 + Math.min(1, Math.abs(tile.act) / 100) * (r - 20), live ? Theme.fb : Theme.dim, 4)
                }
                g.fillStyle = Theme.text; g.beginPath(); g.arc(c, cy, 4, 0, 2 * Math.PI); g.fill()
            }
            Connections { target: tile; function onTChanged() { dial.requestPaint() } }
        }

        // ── числа и полоса упора ──
        ColumnLayout {
            anchors.left: dial.right; anchors.leftMargin: 4; anchors.right: parent.right
            anchors.top: idl.bottom; anchors.topMargin: 10
            spacing: 3

            Row2 { label: "упор"; value: t.fb ? Theme.num(t.thrustKN, 0) + " кН" : "—" }

            // полоса −100…+100 %: ноль посередине, факт — заливка, задание — риска
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: 30
                Rectangle { id: bar; width: parent.width; height: 12; y: 4; radius: 2; color: Theme.bg; border.color: Theme.line }
                Rectangle {
                    readonly property real p: Math.max(-1, Math.min(1, tile.act / 100))
                    y: bar.y + 3; height: bar.height - 6; radius: 1
                    width: Math.abs(p) * (bar.width / 2 - 2)
                    x: p >= 0 ? bar.width / 2 : bar.width / 2 - width
                    color: tile.off ? Theme.dim : Math.abs(p) > 0.9 ? Theme.warn : Theme.fb
                }
                Rectangle { x: bar.width / 2 - 1; y: bar.y - 3; width: 2; height: bar.height + 6; color: Theme.dim }
                Rectangle {
                    readonly property real p: Math.max(-1, Math.min(1, tile.cmd / 100))
                    x: bar.width / 2 + p * (bar.width / 2 - 2) - 1.5; y: bar.y - 4; width: 3; height: bar.height + 8; color: Theme.accent
                }
                Label { x: 0; y: bar.y + bar.height + 1; text: "−100"; color: Theme.dim; font.pixelSize: 10; font.family: Theme.mono }
                Label { anchors.horizontalCenter: bar.horizontalCenter; y: bar.y + bar.height + 1; text: "0"; color: Theme.dim; font.pixelSize: 10; font.family: Theme.mono }
                Label { anchors.right: bar.right; y: bar.y + bar.height + 1; text: "+100 %"; color: Theme.dim; font.pixelSize: 10; font.family: Theme.mono }
            }

            Row2 {
                label: "зад. / факт"
                value: Theme.num(tile.cmd, 0) + " / " + (t.fb ? Theme.num(tile.act, 0) : "—") + " %"
                valueColor: tile.lag ? Theme.warn : Theme.text
            }
            Row2 {
                visible: tile.az
                label: "угол з / ф"
                value: Theme.bearing(t.cmdAng) + " / " + (t.fb ? Theme.bearing(t.fbAng) : "—")
                valueColor: t.fb && Math.abs(((t.cmdAng - t.fbAng) % 360 + 540) % 360 - 180) > 15 ? Theme.warn : Theme.text
            }
            Row2 {     // оценка ядра по упору и кривой движителя
                label: "мощн. / обор."
                value: Theme.num(t.powerKW, 0) + " кВт / " + Theme.num(t.rpmPct, 0) + " %"
                valueColor: t.powerMaxKW > 0 && t.powerKW > 0.9 * t.powerMaxKW ? Theme.warn : Theme.text
            }
        }

        // ── условные обозначения внизу ──
        Label {
            anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
            text: tile.az ? "△ задание · ➤ факт · 0° — упор к носу" : "│ задание · ━ факт упора"
            color: Theme.dim; font.pixelSize: 11; elide: Text.ElideRight
        }
    }
}
