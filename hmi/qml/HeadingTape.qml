import QtQuick

// Лента курса: текущий курс крупно, шкала ±25° и метка заданного курса
Item {
    id: tp
    readonly property var st: backend.s
    readonly property real psi: st.psi === undefined ? 0 : st.psi
    Connections { target: backend; function onUpdated() { tape.requestPaint() } }
    Connections { target: Theme; function onPresetChanged() { tape.requestPaint() } }
    Text { anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
           width: parent.width; height: parent.height - tape.height - Theme.px(2); fontSizeMode: Text.Fit; minimumPixelSize: 12; font.pixelSize: 44
           horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
           text: Theme.f(tp.psi, 1) + "°"; color: Theme.text; font.bold: true; font.family: Theme.mono }
    Canvas {
        id: tape
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Math.min(parent.height * 0.5, Theme.px(46))
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
            var half = 25, ppd = width / (2 * half), cx = width / 2, psi = tp.psi
            ctx.font = Theme.px(11) + "px sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "top"; ctx.lineWidth = 1
            for (var d = Math.floor(psi - half); d <= Math.ceil(psi + half); ++d) {
                var x = cx + (d - psi) * ppd, n = ((d % 360) + 360) % 360, len = (n % 10 === 0) ? 14 : (n % 5 === 0) ? 10 : 6
                ctx.strokeStyle = Qt.rgba(Theme.sub.r, Theme.sub.g, Theme.sub.b, n % 5 === 0 ? 0.95 : 0.55)
                ctx.beginPath(); ctx.moveTo(x, 2); ctx.lineTo(x, 2 + len); ctx.stroke()
                if (n % 10 === 0) { ctx.fillStyle = Theme.sub; ctx.fillText(String(n), x, 18) }
            }
            if (st.mode !== 0 && st.mode !== 1 || st.spPending) {
                var dd = ((((st.spPsi || 0) - psi + 180) % 360) + 360) % 360 - 180
                if (Math.abs(dd) <= half) { var xs = cx + dd * ppd; ctx.fillStyle = Theme.warn
                    ctx.beginPath(); ctx.moveTo(xs - 6, height - 2); ctx.lineTo(xs + 6, height - 2); ctx.lineTo(xs, height - 12); ctx.closePath(); ctx.fill() }
            }
            ctx.strokeStyle = Theme.accent; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(cx, 0); ctx.lineTo(cx, height); ctx.stroke()
        }
    }
}
