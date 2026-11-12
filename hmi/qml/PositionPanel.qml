import QtQuick

// «Заданная позиция»: лента курса с ROT и пределом поворота, ΔС/ΔВ, расстояние и пеленг до точки, широта и долгота точки
Rectangle {
    id: pp
    readonly property var st: backend.s
    color: Theme.panel; radius: 8; border.color: Theme.line
    implicitHeight: Theme.px(360)

    readonly property real dn: (st.spN || 0) - (st.n || 0)
    readonly property real de: (st.spE || 0) - (st.e || 0)
    readonly property real dist: Math.hypot(dn, de)
    readonly property real brg: { var b = Math.atan2(de, dn) * 180 / Math.PI; return b < 0 ? b + 360 : b }
    readonly property var geo: backend.geoOf(st.spN || 0, st.spE || 0)
    function nice(v) { var k = Math.pow(10, Math.floor(Math.log(v) / Math.LN10)), m = v / k; return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 5 ? 5 : 10) * k }
    readonly property real range: nice(Math.max(10, dist * 1.25))

    Text { x: Theme.px(12); y: Theme.px(8); text: "ЗАДАННАЯ ПОЗИЦИЯ"; color: Theme.accent; font.pixelSize: Theme.px(14); font.bold: true; font.letterSpacing: 0.6 }
    HeadingTape { id: tape; x: Theme.px(10); y: Theme.px(32); width: parent.width - Theme.px(20); height: Theme.px(78) }
    Row {
        id: rotRow; x: Theme.px(12); y: Theme.px(114); width: parent.width - Theme.px(24); spacing: Theme.px(8)
        Text { text: "ROT"; color: Theme.sub; font.pixelSize: Theme.px(14); anchors.verticalCenter: parent.verticalCenter }
        Text { text: Theme.f(st.rot, 1); color: Math.abs(st.rot || 0) > (st.capRot > 0 ? st.capRot : 1e9) ? Theme.warn : Theme.text; font.pixelSize: Theme.px(22); font.bold: true; font.family: Theme.mono; anchors.verticalCenter: parent.verticalCenter }
        Text { text: "°/мин"; color: Theme.sub; font.pixelSize: Theme.px(11); anchors.verticalCenter: parent.verticalCenter }
        Item { width: 1; height: 1 }
        Text { text: "Лимит: " + (st.capRot > 0 ? Theme.f(st.capRot, 1) + " °/мин" : "нет"); color: st.capRot > 0 ? Theme.warn : Theme.sub; font.pixelSize: Theme.px(12); anchors.verticalCenter: parent.verticalCenter }
    }
    Row {
        x: Theme.px(12); y: Theme.px(142); spacing: Theme.px(8)
        Text { text: "SOG"; color: Theme.sub; font.pixelSize: Theme.px(14); anchors.verticalCenter: parent.verticalCenter }
        Text { text: Theme.num(Theme.speedV(st.speed || 0), 2); color: Theme.text; font.pixelSize: Theme.px(20); font.bold: true; font.family: Theme.mono; anchors.verticalCenter: parent.verticalCenter }
        Text { text: Theme.speedU(); color: Theme.sub; font.pixelSize: Theme.px(11); anchors.verticalCenter: parent.verticalCenter }
        Text { text: st.capSpeed > 0 ? "   Лимит: " + Theme.speed(st.capSpeed * 0.514444, 2) : "   Лимит: нет"; color: st.capSpeed > 0 ? Theme.warn : Theme.sub; font.pixelSize: Theme.px(12); anchors.verticalCenter: parent.verticalCenter }
    }
    Rectangle { x: Theme.px(10); y: Theme.px(172); width: parent.width - Theme.px(20); height: 1; color: Theme.line }

    // мини-компас: судно в центре, зелёная точка — заданная позиция
    Canvas {
        id: mini
        x: Theme.px(10); y: Theme.px(180); width: Theme.px(124); height: width
        Connections { target: backend; function onUpdated() { mini.requestPaint() } }
        Connections { target: Theme; function onPresetChanged() { mini.requestPaint() } }
        onPaint: {
            var ctx = getContext("2d"); ctx.clearRect(0, 0, width, height)
            var cx = width / 2, cy = height / 2, R = width / 2 - 16
            ctx.strokeStyle = Theme.line; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(cx, cy, R, 0, 2 * Math.PI); ctx.stroke()
            ctx.beginPath(); ctx.arc(cx, cy, R / 2, 0, 2 * Math.PI); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(cx - R, cy); ctx.lineTo(cx + R, cy); ctx.moveTo(cx, cy - R); ctx.lineTo(cx, cy + R); ctx.stroke()
            ctx.fillStyle = Theme.text; ctx.font = Theme.px(11) + "px sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle"
            ctx.fillText("С", cx, cy - R - 8); ctx.fillText("Ю", cx, cy + R + 8); ctx.fillText("В", cx + R + 8, cy); ctx.fillText("З", cx - R - 8, cy)
            // судно по курсу
            ctx.save(); ctx.translate(cx, cy); ctx.rotate((st.psi || 0) * Math.PI / 180)
            ctx.fillStyle = Theme.hull; ctx.strokeStyle = Theme.text; ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(0, -10); ctx.lineTo(5, -4); ctx.lineTo(5, 9); ctx.lineTo(-5, 9); ctx.lineTo(-5, -4); ctx.closePath(); ctx.fill(); ctx.stroke(); ctx.restore()
            // заданная точка
            var k = R / pp.range, px = cx + pp.de * k, py = cy - pp.dn * k
            var out = Math.hypot(px - cx, py - cy) > R; if (out) { var a = Math.atan2(py - cy, px - cx); px = cx + R * Math.cos(a); py = cy + R * Math.sin(a) }
            ctx.strokeStyle = Theme.ok; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(px, py, 4, 0, 2 * Math.PI); ctx.stroke()
        }
    }
    Column {
        x: Theme.px(140); y: Theme.px(184); width: parent.width - Theme.px(150); spacing: 1
        Row { width: parent.width; Text { text: "ΔС"; color: Theme.sub; font.pixelSize: Theme.px(13); width: parent.width * 0.4 }
              Text { text: (pp.dn >= 0 ? "+" : "−") + Theme.dist(Math.abs(pp.dn), 1); color: Theme.text; font.pixelSize: Theme.px(14); font.bold: true; font.family: Theme.mono } }
        Row { width: parent.width; Text { text: "ΔВ"; color: Theme.sub; font.pixelSize: Theme.px(13); width: parent.width * 0.4 }
              Text { text: (pp.de >= 0 ? "+" : "−") + Theme.dist(Math.abs(pp.de), 1); color: Theme.text; font.pixelSize: Theme.px(14); font.bold: true; font.family: Theme.mono } }
        Row { width: parent.width; Text { text: "Расст."; color: Theme.sub; font.pixelSize: Theme.px(13); width: parent.width * 0.4 }
              Text { text: Theme.dist(pp.dist, 1); color: pp.dist > 5 ? Theme.warn : Theme.text; font.pixelSize: Theme.px(14); font.bold: true; font.family: Theme.mono } }
        Row { width: parent.width; Text { text: "Пеленг"; color: Theme.sub; font.pixelSize: Theme.px(13); width: parent.width * 0.4 }
              Text { text: Theme.f(pp.brg, 1) + "°"; color: Theme.text; font.pixelSize: Theme.px(14); font.bold: true; font.family: Theme.mono } }
        Text { text: "Круг = " + Theme.dist(pp.range, 0); color: Theme.sub; font.pixelSize: Theme.px(11) }
    }
    Rectangle { x: Theme.px(10); y: Theme.px(312); width: parent.width - Theme.px(20); height: 1; color: Theme.line }
    Text { x: Theme.px(12); y: Theme.px(318); text: "Позиция (заданная)"; color: Theme.sub; font.pixelSize: Theme.px(11) }
    Row { x: Theme.px(12); y: Theme.px(334); spacing: Theme.px(14)
        Text { text: "LAT  " + (pp.geo && pp.geo.valid ? Theme.coord(pp.geo.lat, true, 2) : "—"); color: Theme.text; font.pixelSize: Theme.px(12); font.family: Theme.mono }
        Text { text: "LON  " + (pp.geo && pp.geo.valid ? Theme.coord(pp.geo.lon, false, 2) : "—"); color: Theme.text; font.pixelSize: Theme.px(12); font.family: Theme.mono } }
}
