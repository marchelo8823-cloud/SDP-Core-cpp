import QtQuick

// Диаграмма качества опорной системы: отклонения последних измерений от решения (север вверх, восток вправо), м.
// Окружности: заявленное СКО (зелёная) и измеренная повторяемость (янтарная/красная при превышении порога).
Item {
    id: d
    property string scat: ""          // «n,e;n,e;…» в сантиметрах
    property real sigma: 0.5          // заявленное СКО, м
    property real sdRep: 0            // повторяемость, м (0 — ещё не оценена)
    property bool bad: false
    property var pts: {
        var r = []
        if (scat === "") return r
        var a = scat.split(";")
        for (var i = 0; i < a.length; ++i) { var p = a[i].split(","); if (p.length === 2) r.push([parseFloat(p[0]) / 100, parseFloat(p[1]) / 100]) }
        return r
    }
    onPtsChanged: cv.requestPaint()
    onSigmaChanged: cv.requestPaint()
    onSdRepChanged: cv.requestPaint()
    Canvas {
        id: cv
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            var w = width, h = height, cx = w / 2, cy = h / 2
            ctx.fillStyle = Theme.plan; ctx.fillRect(0, 0, w, h)
            var m = Math.max(d.sigma * 2.2, d.sdRep * 2.2, 0.3)
            for (var i = 0; i < d.pts.length; ++i) m = Math.max(m, Math.abs(d.pts[i][0]) * 1.15, Math.abs(d.pts[i][1]) * 1.15)
            var s = Math.min(w, h) / 2 / m
            ctx.strokeStyle = Theme.line; ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(0, cy); ctx.lineTo(w, cy); ctx.moveTo(cx, 0); ctx.lineTo(cx, h); ctx.stroke()
            ctx.strokeStyle = Theme.ok; ctx.beginPath(); ctx.arc(cx, cy, d.sigma * s, 0, 2 * Math.PI); ctx.stroke()
            if (d.sdRep > 0) { ctx.strokeStyle = d.bad ? Theme.bad : Theme.warn; ctx.beginPath(); ctx.arc(cx, cy, d.sdRep * s, 0, 2 * Math.PI); ctx.stroke() }
            ctx.fillStyle = Theme.accent
            for (var k = 0; k < d.pts.length; ++k) {
                ctx.globalAlpha = 0.25 + 0.75 * (k + 1) / d.pts.length
                ctx.beginPath(); ctx.arc(cx + d.pts[k][1] * s, cy - d.pts[k][0] * s, 2.5, 0, 2 * Math.PI); ctx.fill()
            }
            ctx.globalAlpha = 1
            ctx.fillStyle = Theme.sub; ctx.font = "11px sans-serif"
            ctx.fillText("С", cx + 4, 11); ctx.fillText("В", w - 12, cy - 4)
            ctx.fillText(m.toFixed(1) + " м", 4, h - 4)
        }
    }
}
