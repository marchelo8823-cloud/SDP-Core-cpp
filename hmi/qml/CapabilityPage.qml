import QtQuick
import QtQuick.Controls

// Окно «Возможности судна» (capability plot): предельный ветер по направлениям, при котором комплекс ещё удерживает судно.
// Сплошная линия — предел при полном упоре, штриховая — рабочий предел при 80 % упора. Нос вверху; направление — откуда дует ветер.
// Волна и течение идут с того же направления, что и ветер. ⚠ Оценка по модели ядра (средние силы, без порывов и качки),
// не расчёт по правилам классификационного общества.
Item {
    id: pg
    readonly property var st: backend.s
    property var curves: []
    property var picked: ({})            // номер сценария -> показан ли
    property int curIdx: 2               // выбор течения
    property int mode: 0                 // 0 — диаграмма, 1 — гипотеза и дрейф
    property int wavIdx: 1               // 0 — без волн, 1 — волна по ветру
    readonly property var curVals: [0, 0.25, 0.5, 1.0, 1.5]
    readonly property var palette: ["#4cc9f0", "#ff9f1c", "#e63946", "#2ec27e", "#c77dff", "#f7d154", "#ff6fb5", "#9aa5b1"]

    function recompute() {
        var c = backend.capabilityPlot(curVals[curIdx], wavIdx === 1)
        curves = c
        var p = {}
        for (var i = 0; i < c.length; ++i) p[i] = (picked[i] !== undefined) ? picked[i] : (i < 2)
        picked = p
        plot.requestPaint()
    }
    onVisibleChanged: if (visible) recompute()
    Component.onCompleted: if (visible) recompute()
    function togg(i) { var p = Object.assign({}, picked); p[i] = !p[i]; picked = p; plot.requestPaint() }
    function fmt(v) { return v >= 39.9 ? "> 40" : v.toFixed(1) }
    // предел по направлению (линейная интерполяция) для первого сценария — «все движители»
    function limitAt(c, deg, key) {
        if (!c || !c.dir || c.dir.length < 2) return 0
        var step = 360 / c.dir.length, d = ((deg % 360) + 360) % 360
        var i0 = Math.floor(d / step) % c.dir.length, i1 = (i0 + 1) % c.dir.length, f = (d - i0 * step) / step
        return c[key][i0] + f * (c[key][i1] - c[key][i0])
    }
    readonly property real windNow: st.windValid ? st.windSpeed : 0
    readonly property real windRel: st.windFromRel || 0
    readonly property real usePct: curves.length > 0 && windNow > 0 ? 100 * windNow / Math.max(0.1, limitAt(curves[0], windRel, "limit")) : 0

    Rectangle { anchors.fill: parent; radius: 8; color: Theme.panel; border.color: Theme.line }

    // ---- шапка и параметры
    Text { x: Theme.px(16); y: Theme.px(10); text: "ВОЗМОЖНОСТИ СУДНА"; color: Theme.text; font.pixelSize: Theme.px(18); font.bold: true }
    Text { x: Theme.px(16); y: Theme.px(36); width: parent.width - Theme.px(32); elide: Text.ElideRight
           text: "Предельный ветер по направлениям: сплошная линия — полный упор, штриховая — рабочий предел 80 % упора. Волна и течение — с того же направления, что и ветер."
           color: Theme.sub; font.pixelSize: Theme.px(13) }
    Seg { id: modeSw; anchors { right: parent.right; rightMargin: Theme.px(130); top: parent.top; topMargin: Theme.px(2) } width: Theme.px(300); height: Theme.px(32); px: Theme.px(13)
          model: ["Диаграмма", "Гипотеза и дрейф"]; current: pg.mode; onPicked: (i) => { pg.mode = i; if (i === 0) pg.recompute() } }
    HypotPanel { visible: pg.mode === 1; anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: Theme.px(16); rightMargin: Theme.px(16); topMargin: Theme.px(66); bottomMargin: Theme.px(10) } }
    Chip { anchors { right: parent.right; top: parent.top; margins: Theme.px(14) } text: "ИМИТАЦИЯ"; tone: Theme.warn; solid: true; visible: st.sim }

    // ---- левая колонка: параметры и сценарии
    Column {
        id: side
        visible: pg.mode === 0
        x: Theme.px(16); y: Theme.px(66); width: Theme.px(300); spacing: Theme.px(8)
        Text { text: "Течение, м/с"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true }
        Seg { width: parent.width; height: Theme.px(34); px: Theme.px(13); model: ["0", "0,25", "0,5", "1,0", "1,5"]; current: pg.curIdx
              onPicked: (i) => { pg.curIdx = i; pg.recompute() } }
        Item { width: 1; height: Theme.px(2) }
        Text { text: "Волнение"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true }
        Seg { width: parent.width; height: Theme.px(34); px: Theme.px(13); model: ["Нет", "По ветру"]; current: pg.wavIdx
              onPicked: (i) => { pg.wavIdx = i; pg.recompute() } }
        Item { width: 1; height: Theme.px(4) }
        Text { text: "Сценарии"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true }
        Repeater {
            model: pg.curves.length
            delegate: Rectangle {
                required property int index
                readonly property var c: pg.curves[index]
                readonly property bool on: pg.picked[index] === true
                width: side.width; height: Theme.px(34); radius: 4
                color: on ? Theme.panel2 : "transparent"; border.color: on ? pg.palette[index % pg.palette.length] : Theme.line; border.width: on ? 2 : 1
                Rectangle { x: Theme.px(8); anchors.verticalCenter: parent.verticalCenter; width: Theme.px(16); height: Theme.px(16); radius: 3
                            color: parent.on ? pg.palette[index % pg.palette.length] : "transparent"; border.color: pg.palette[index % pg.palette.length] }
                Text { x: Theme.px(34); anchors.verticalCenter: parent.verticalCenter; text: c ? c.name : ""; color: Theme.text; font.pixelSize: Theme.px(14) }
                Text { anchors { right: parent.right; rightMargin: Theme.px(8); verticalCenter: parent.verticalCenter }
                       text: c ? (c.minLimit < 0.05 ? "не везде держит" : "от " + pg.fmt(c.minLimit) + " м/с") : ""; color: c && c.minLimit < 0.05 ? Theme.bad : Theme.sub; font.pixelSize: Theme.px(12) }
                MouseArea { anchors.fill: parent; onClicked: pg.togg(index) }
            }
        }
    }

    // ---- полярная диаграмма
    Canvas {
        id: plot
        visible: pg.mode === 0
        anchors { left: side.right; leftMargin: Theme.px(16); right: info.left; rightMargin: Theme.px(16); top: parent.top; topMargin: Theme.px(62); bottom: parent.bottom; bottomMargin: Theme.px(14) }
        onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
        Connections { target: backend; function onUpdated() { if (pg.visible) plot.requestPaint() } }
        Connections { target: Theme; function onPresetChanged() { plot.requestPaint() } }
        onPaint: {
            var ctx = getContext("2d"); ctx.reset()
            var w = width, h = height, cx = w / 2, cy = h / 2, R = Math.max(40, Math.min(w, h) / 2 - Theme.px(44))
            // масштаб: до ближайшего «круглого» значения выше наибольшего предела среди показанных сценариев
            var mx = 10
            for (var i = 0; i < pg.curves.length; ++i) if (pg.picked[i]) mx = Math.max(mx, Math.max.apply(null, pg.curves[i].limit))
            var ring = mx > 30 ? 10 : 5
            mx = Math.min(40, Math.ceil(mx / ring) * ring)
            function pt(deg, v) { var a = deg * Math.PI / 180, r = R * v / mx; return [cx + r * Math.sin(a), cy - r * Math.cos(a)] }
            ctx.lineWidth = 1; ctx.strokeStyle = Theme.grid; ctx.fillStyle = Theme.sub; ctx.font = Math.round(Theme.px(12)) + "px sans-serif"
            for (var v = ring; v <= mx; v += ring) {
                ctx.beginPath(); ctx.arc(cx, cy, R * v / mx, 0, 2 * Math.PI); ctx.stroke()
                ctx.fillText(v + " м/с", cx + 4, cy - R * v / mx + Theme.px(13))
            }
            ctx.textAlign = "center"
            for (var a = 0; a < 360; a += 30) {
                var p0 = pt(a, 0), p1 = pt(a, mx), pl = pt(a, mx * 1.0 + (mx * 0.07))
                ctx.beginPath(); ctx.moveTo(p0[0], p0[1]); ctx.lineTo(p1[0], p1[1]); ctx.stroke()
                ctx.fillText(a + "°", pl[0], pl[1] + Theme.px(4))
            }
            ctx.textAlign = "left"
            // судно: контур, нос вверху
            var sl = R * 0.16, sw = R * 0.05
            ctx.fillStyle = Theme.hull; ctx.strokeStyle = Theme.line; ctx.beginPath()
            ctx.moveTo(cx, cy - sl); ctx.lineTo(cx + sw, cy - sl * 0.45); ctx.lineTo(cx + sw, cy + sl * 0.85); ctx.lineTo(cx - sw, cy + sl * 0.85); ctx.lineTo(cx - sw, cy - sl * 0.45); ctx.closePath()
            ctx.fill(); ctx.stroke()
            // кривые
            function draw(c, key, color, dash) {
                ctx.beginPath(); ctx.strokeStyle = color; ctx.lineWidth = dash ? 2 : 3; ctx.setLineDash(dash ? [7, 5] : [])
                var n = c.dir.length
                for (var k = 0; k <= n; ++k) { var q = pt(c.dir[k % n], Math.min(c[key][k % n], mx)); if (k === 0) ctx.moveTo(q[0], q[1]); else ctx.lineTo(q[0], q[1]) }
                ctx.stroke(); ctx.setLineDash([])
            }
            for (var j = pg.curves.length - 1; j >= 0; --j) {
                if (!pg.picked[j]) continue
                var col = pg.palette[j % pg.palette.length]
                draw(pg.curves[j], "work", col, true); draw(pg.curves[j], "limit", col, false)
            }
            // текущий ветер
            if (pg.windNow > 0) {
                var q = pt(pg.windRel, Math.min(pg.windNow, mx))
                ctx.fillStyle = Theme.bad; ctx.strokeStyle = Theme.text; ctx.lineWidth = 2
                ctx.beginPath(); ctx.arc(q[0], q[1], Theme.px(7), 0, 2 * Math.PI); ctx.fill(); ctx.stroke()
                ctx.fillStyle = Theme.text; ctx.fillText("ветер сейчас", q[0] + Theme.px(10), q[1] + Theme.px(4))
            }
        }
    }

    // ---- справа: таблица и пояснения
    Column {
        id: info
        visible: pg.mode === 0
        anchors { right: parent.right; rightMargin: Theme.px(16); top: parent.top; topMargin: Theme.px(66) }
        width: Theme.px(300); spacing: Theme.px(8)
        Text { text: "Ветер сейчас"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true }
        Text { width: info.width; wrapMode: Text.WordWrap; color: Theme.text; font.pixelSize: Theme.px(15)
               text: pg.windNow > 0 ? pg.windNow.toFixed(1) + " м/с, с направления " + Math.round(((pg.windRel % 360) + 360) % 360) + "°" : "нет данных о ветре" }
        Text { width: info.width; wrapMode: Text.WordWrap; font.pixelSize: Theme.px(14); font.bold: true
               visible: pg.curves.length > 0 && pg.windNow > 0
               color: pg.usePct >= 100 ? Theme.bad : pg.usePct >= 80 ? Theme.warn : Theme.ok
               text: "Это " + Math.round(pg.usePct) + " % предела при всех движителях в этом направлении" + (pg.usePct >= 100 ? ". Предел превышен." : pg.usePct >= 80 ? ". Выше рабочего предела." : ".") }
        Item { width: 1; height: Theme.px(6) }
        Text { text: "Худшее направление, м/с"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true }
        Repeater {
            model: pg.curves.length
            delegate: Item {
                required property int index
                readonly property var c: pg.curves[index]
                width: info.width; height: Theme.px(22)
                visible: pg.picked[index] === true
                Rectangle { width: Theme.px(10); height: Theme.px(10); radius: 2; anchors.verticalCenter: parent.verticalCenter; color: pg.palette[index % pg.palette.length] }
                Text { x: Theme.px(16); anchors.verticalCenter: parent.verticalCenter; text: c ? c.name : ""; color: Theme.text; font.pixelSize: Theme.px(13) }
                Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter } font.family: Theme.mono; font.pixelSize: Theme.px(13)
                       color: c && c.minLimit < 0.05 ? Theme.bad : Theme.text
                       text: c ? (c.minLimit < 0.05 ? "не везде держит" : pg.fmt(c.minLimit) + " / " + pg.fmt(c.minWork) + "  (" + Math.round(c.minDir) + "°)") : "" }
            }
        }
        Text { width: info.width; wrapMode: Text.WordWrap; color: Theme.sub; font.pixelSize: Theme.px(12)
               text: "В строке: предел / рабочий (80 % упора), в скобках направление ветра с наименьшим пределом. «Не везде держит» — при ветре с части направлений комплекс не удерживает судно даже при штиле и заданном течении." }
        Item { width: 1; height: Theme.px(6) }
        Text { width: info.width; wrapMode: Text.WordWrap; color: Theme.warn; font.pixelSize: Theme.px(12)
               text: "⚠ Оценка по модели: средние силы, без порывов и качки; курс постоянный; ветер, волна и течение с одного направления; волна по ветру — развитое волнение (Hs = 0,0246·V²). Не расчёт по правилам РС или DNV." }
    }
}
