import QtQuick
import QtQuick.Controls

// Центр вращения судна: точка на судне, вокруг которой поворачивается курс при подтверждении поворота.
// Координаты в связанных осях: «вдоль» — от миделя к носу (+), «поперёк» — к правому борту (+). Значение хранится в настройках поста.
Popup {
    id: pop
    modal: true; focus: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 40 : 560, Theme.px(560))
    padding: Theme.px(16)
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    property real px: 0          // вдоль, м (+ нос)
    property real py: 0          // поперёк, м (+ правый борт)
    property real shipLen: 60
    property real shipBeam: 14
    signal applied(real x, real y)
    function set(x, y) { px = Math.round(Math.max(-shipLen, Math.min(shipLen, x)) * 10) / 10; py = Math.round(Math.max(-shipBeam, Math.min(shipBeam, y)) * 10) / 10; applied(px, py); pv.requestPaint() }
    onPxChanged: pv.requestPaint()
    onPyChanged: pv.requestPaint()
    background: Rectangle { color: Theme.panel; radius: 10; border.color: Theme.line; border.width: 1 }

    contentItem: Column {
        spacing: Theme.px(10)
        Text { text: "Центр вращения"; color: Theme.text; font.pixelSize: Theme.px(20); font.bold: true }
        Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(13)
               text: "Судно поворачивается вокруг выбранной точки. При подтверждении поворота точка удержания смещается так, чтобы эта точка осталась на месте. Мидель (0; 0) — поворот без смещения точки удержания." }
        Row {
            spacing: Theme.px(14)
            Canvas {
                id: pv
                width: Theme.px(120); height: Theme.px(200)
                onPaint: {
                    var c = getContext("2d"); c.clearRect(0, 0, width, height)
                    var L = height * 0.88, B = width * 0.50, x0 = width / 2, y0 = height / 2
                    c.beginPath(); c.moveTo(x0, y0 - L / 2); c.lineTo(x0 + B / 2, y0 - L / 6); c.lineTo(x0 + B / 2, y0 + L / 2); c.lineTo(x0 - B / 2, y0 + L / 2); c.lineTo(x0 - B / 2, y0 - L / 6); c.closePath()
                    c.fillStyle = Qt.rgba(Theme.panel2.r, Theme.panel2.g, Theme.panel2.b, 1); c.fill()
                    c.lineWidth = 2; c.strokeStyle = Theme.hull; c.stroke()
                    c.strokeStyle = Qt.rgba(Theme.sub.r, Theme.sub.g, Theme.sub.b, 0.5); c.lineWidth = 1
                    c.beginPath(); c.moveTo(x0, y0 - L / 2 - 6); c.lineTo(x0, y0 + L / 2 + 6); c.moveTo(x0 - B / 2 - 6, y0); c.lineTo(x0 + B / 2 + 6, y0); c.stroke()
                    var px = x0 + pop.py / Math.max(1, pop.shipBeam) * B, py = y0 - pop.px / Math.max(1, pop.shipLen) * L
                    c.strokeStyle = Theme.accent; c.fillStyle = Theme.accent; c.lineWidth = 2
                    c.beginPath(); c.arc(px, py, 7, 0, 2 * Math.PI); c.stroke()
                    c.beginPath(); c.arc(px, py, 2.5, 0, 2 * Math.PI); c.fill()
                    c.fillStyle = Theme.sub; c.font = Theme.px(11) + "px sans-serif"; c.textAlign = "center"; c.fillText("нос", x0, 10)
                }
                MouseArea {      // точку можно поставить и касанием по силуэту
                    anchors.fill: parent
                    function put(m) {
                        var L = pv.height * 0.88, B = pv.width * 0.50
                        pop.set(-(m.y - pv.height / 2) / L * pop.shipLen, (m.x - pv.width / 2) / B * pop.shipBeam)
                    }
                    onPressed: (m) => put(m)
                    onPositionChanged: (m) => { if (pressed) put(m) }
                }
            }
            Column {
                spacing: Theme.px(8)
                Text { text: "Вдоль судна, м (+ к носу)"; color: Theme.sub; font.pixelSize: Theme.px(13) }
                Row { spacing: 6
                    Btn { text: "−5"; width: Theme.px(50); onClicked: pop.set(pop.px - 5, pop.py) }
                    Btn { text: "−1"; width: Theme.px(50); onClicked: pop.set(pop.px - 1, pop.py) }
                    Text { width: Theme.px(70); height: Theme.px(40); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: (pop.px > 0 ? "+" : "") + pop.px.toFixed(1); color: Theme.accent; font.pixelSize: Theme.px(22); font.bold: true; font.family: Theme.mono }
                    Btn { text: "+1"; width: Theme.px(50); onClicked: pop.set(pop.px + 1, pop.py) }
                    Btn { text: "+5"; width: Theme.px(50); onClicked: pop.set(pop.px + 5, pop.py) }
                }
                Text { text: "Поперёк, м (+ к правому борту)"; color: Theme.sub; font.pixelSize: Theme.px(13) }
                Row { spacing: 6
                    Btn { text: "−1"; width: Theme.px(50); onClicked: pop.set(pop.px, pop.py - 1) }
                    Btn { text: "−0.1"; width: Theme.px(50); onClicked: pop.set(pop.px, pop.py - 0.1) }
                    Text { width: Theme.px(70); height: Theme.px(40); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; text: (pop.py > 0 ? "+" : "") + pop.py.toFixed(1); color: Theme.accent; font.pixelSize: Theme.px(22); font.bold: true; font.family: Theme.mono }
                    Btn { text: "+0.1"; width: Theme.px(50); onClicked: pop.set(pop.px, pop.py + 0.1) }
                    Btn { text: "+1"; width: Theme.px(50); onClicked: pop.set(pop.px, pop.py + 1) }
                }
                Text { text: "Готовые варианты"; color: Theme.sub; font.pixelSize: Theme.px(13) }
                Flow { width: Theme.px(330); spacing: 6
                    Btn { text: "Мидель"; onClicked: pop.set(0, 0) }
                    Btn { text: "Нос"; onClicked: pop.set(pop.shipLen / 2, 0) }
                    Btn { text: "Корма"; onClicked: pop.set(-pop.shipLen / 2, 0) }
                    Btn { text: "¼ от носа"; onClicked: pop.set(pop.shipLen / 4, 0) }
                    Btn { text: "¼ от кормы"; onClicked: pop.set(-pop.shipLen / 4, 0) }
                }
            }
        }
        Row { spacing: 8; anchors.right: parent.right
            Btn { text: "Готово"; active: true; onClicked: pop.close() }
        }
    }
}
