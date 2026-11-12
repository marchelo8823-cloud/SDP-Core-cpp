import QtQuick

// Значок страницы для боковой панели (рисуется линиями, без файлов изображений)
Canvas {
    id: ic
    property string kind: ""
    property color tone: Theme.text
    width: Theme.px(30); height: width
    onToneChanged: requestPaint()
    onKindChanged: requestPaint()
    onWidthChanged: requestPaint()
    Connections { target: Theme; function onPresetChanged() { ic.requestPaint() } }
    onPaint: {
        var ctx = getContext("2d"); ctx.reset(); ctx.clearRect(0, 0, width, height)
        var w = width, u = w / 30
        ctx.strokeStyle = tone; ctx.fillStyle = tone; ctx.lineWidth = 2 * u; ctx.lineJoin = "round"; ctx.lineCap = "round"
        function circ(x, y, r) { ctx.beginPath(); ctx.arc(x * u, y * u, r * u, 0, 2 * Math.PI) }
        function line(x0, y0, x1, y1) { ctx.beginPath(); ctx.moveTo(x0 * u, y0 * u); ctx.lineTo(x1 * u, y1 * u); ctx.stroke() }
        switch (kind) {
        case "work":      // карта: сложенный лист
            ctx.beginPath(); ctx.moveTo(4 * u, 8 * u); ctx.lineTo(11 * u, 5 * u); ctx.lineTo(19 * u, 8 * u); ctx.lineTo(26 * u, 5 * u); ctx.lineTo(26 * u, 22 * u)
            ctx.lineTo(19 * u, 25 * u); ctx.lineTo(11 * u, 22 * u); ctx.lineTo(4 * u, 25 * u); ctx.closePath(); ctx.stroke()
            line(11, 5, 11, 22); line(19, 8, 19, 25); break
        case "sensors":   // слои
            ctx.beginPath(); ctx.moveTo(15 * u, 5 * u); ctx.lineTo(26 * u, 11 * u); ctx.lineTo(15 * u, 17 * u); ctx.lineTo(4 * u, 11 * u); ctx.closePath(); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(4 * u, 16 * u); ctx.lineTo(15 * u, 22 * u); ctx.lineTo(26 * u, 16 * u); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(4 * u, 21 * u); ctx.lineTo(15 * u, 27 * u); ctx.lineTo(26 * u, 21 * u); ctx.stroke(); break
        case "thr":       // винт
            circ(15, 15, 2.5); ctx.fill()
            for (var k = 0; k < 3; ++k) { ctx.save(); ctx.translate(15 * u, 15 * u); ctx.rotate(k * 2 * Math.PI / 3)
                ctx.beginPath(); ctx.ellipse(-3 * u, -12 * u, 6 * u, 10 * u); ctx.stroke(); ctx.restore() } break
        case "pms":       // молния
            ctx.beginPath(); ctx.moveTo(17 * u, 3 * u); ctx.lineTo(7 * u, 17 * u); ctx.lineTo(14 * u, 17 * u); ctx.lineTo(12 * u, 27 * u); ctx.lineTo(23 * u, 12 * u); ctx.lineTo(16 * u, 12 * u); ctx.closePath(); ctx.stroke(); break
        case "cap":       // диаграмма возможностей: многоугольник
            ctx.beginPath(); ctx.moveTo(15 * u, 4 * u); ctx.lineTo(25 * u, 11 * u); ctx.lineTo(22 * u, 24 * u); ctx.lineTo(8 * u, 24 * u); ctx.lineTo(5 * u, 11 * u); ctx.closePath(); ctx.stroke()
            circ(15, 15, 2.5); ctx.fill(); break
        case "fc":        // прогноз: облако
            ctx.beginPath(); ctx.arc(11 * u, 17 * u, 6 * u, Math.PI * 0.5, Math.PI * 1.5); ctx.arc(17 * u, 12 * u, 6 * u, Math.PI * 1.1, Math.PI * 1.9)
            ctx.arc(22 * u, 18 * u, 5 * u, Math.PI * 1.5, Math.PI * 0.5); ctx.closePath(); ctx.stroke(); break
        case "agent":     // помощник: облачко речи
            ctx.beginPath(); ctx.moveTo(5 * u, 6 * u); ctx.lineTo(25 * u, 6 * u); ctx.lineTo(25 * u, 20 * u); ctx.lineTo(13 * u, 20 * u); ctx.lineTo(8 * u, 25 * u); ctx.lineTo(8 * u, 20 * u); ctx.lineTo(5 * u, 20 * u); ctx.closePath(); ctx.stroke()
            line(10, 12, 20, 12); line(10, 16, 17, 16); break
        case "admin":     // шестерёнка
            circ(15, 15, 4); ctx.stroke(); circ(15, 15, 9); ctx.stroke()
            for (var g = 0; g < 8; ++g) { var a = g * Math.PI / 4; line(15 + 9 * Math.cos(a), 15 + 9 * Math.sin(a), 15 + 12.5 * Math.cos(a), 15 + 12.5 * Math.sin(a)) } break
        default:          // меню: три точки
            circ(7, 15, 2); ctx.fill(); circ(15, 15, 2); ctx.fill(); circ(23, 15, 2); ctx.fill()
        }
    }
}
