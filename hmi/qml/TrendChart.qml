// Тренд одной величины: последние значения (раз в 2 с), шкала от 0 (или симметричная), линия предела.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

Rectangle {
    id: root
    property string title: ""
    property string unit: ""
    property var values: []
    property real scale: 1            // множитель для показа (доли → %)
    property real maxv: 10            // верх шкалы (в единицах показа)
    property bool symmetric: false    // шкала от −maxv до +maxv
    property real limit: -1           // линия предела (в единицах показа), −1 — нет
    property color lineColor: Theme.accent
    property int span: 450            // сколько точек на всю ширину (450 × 2 с = 15 мин)
    property string spanText: "15 мин"
    property int digits: 1
    color: Theme.panel; radius: 6

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 12; spacing: 4
        RowLayout {
            Layout.fillWidth: true
            Label { text: root.title; color: Theme.dim; font.pixelSize: Theme.fsSmall; font.bold: true; font.capitalization: Font.AllUppercase; font.letterSpacing: 1; Layout.fillWidth: true }
            Label { text: root.values.length ? Theme.num(root.values[root.values.length - 1] * root.scale, root.digits) + " " + root.unit : "—"; color: Theme.text; font.family: Theme.mono; font.pixelSize: 20 }
        }
        Canvas {
            id: cv
            Layout.fillWidth: true; Layout.fillHeight: true
            onPaint: {
                const g = getContext("2d"); g.reset()
                const W = width, H = height, v = root.values, mx = Math.max(1e-6, root.maxv)
                const y = root.symmetric ? function (x) { return H / 2 - Math.max(-1, Math.min(1, x / mx)) * (H / 2 - 2) }
                                         : function (x) { return H - 2 - Math.max(0, Math.min(1, x / mx)) * (H - 4) }
                g.fillStyle = Theme.plot; g.fillRect(0, 0, W, H)
                g.strokeStyle = Theme.line; g.lineWidth = 1
                for (let i = 1; i < 4; ++i) { g.beginPath(); g.moveTo(0, H * i / 4); g.lineTo(W, H * i / 4); g.stroke() }
                g.fillStyle = Theme.dim; g.font = "11px '" + Theme.font + "'"; g.textAlign = "left"
                g.fillText(Theme.num(root.maxv, 0) + " " + root.unit, 4, 12)
                if (root.limit >= 0) {
                    g.strokeStyle = Theme.alarm; g.globalAlpha = 0.6; g.setLineDash([4, 4])
                    g.beginPath(); g.moveTo(0, y(root.limit)); g.lineTo(W, y(root.limit)); g.stroke()
                    if (root.symmetric) { g.beginPath(); g.moveTo(0, y(-root.limit)); g.lineTo(W, y(-root.limit)); g.stroke() }
                    g.setLineDash([]); g.globalAlpha = 1
                }
                if (v.length < 2) return
                g.strokeStyle = root.lineColor; g.lineWidth = 2; g.beginPath()
                for (let i = 0; i < v.length; ++i) { const x = W - (v.length - 1 - i) * W / (root.span - 1); if (i === 0) g.moveTo(x, y(v[i] * root.scale)); else g.lineTo(x, y(v[i] * root.scale)) }
                g.stroke()
            }
        }
        Label { text: "за " + root.spanText + (root.limit >= 0 ? " · красная линия — " + Theme.num(root.limit, 0) + " " + root.unit : ""); color: Theme.dim; font.pixelSize: 12 }
    }
    onValuesChanged: cv.requestPaint()
}
