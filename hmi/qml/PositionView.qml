// План положения: север вверх, в центре — заданная точка. Судно по оценке ядра, след, движители с векторами упора.
// Правило слоёв: графика (кольца, картушка, судно) — нижний слой и приглушена; цифры — в окнах по углам панели,
// на картушке только значки: курс (заливка) и курс задания (контур) на ободе, ветер и возмущение — стрелки на ободе.
// Подписи колец — на одном диагональном луче, свободном от курса, ветра и возмущения, на подложке.
import QtQuick
import QtQuick.Controls
import "."

Rectangle {
    id: root
    color: Theme.panel
    property var s: ({})
    property var hull: ({})
    property var thrusters: []
    property var track: []
    property real range: 50          // м — радиус внешнего кольца
    property bool followVessel: false
    property bool showLegend: false

    readonly property real windFromTrue: (((s.windFromRel || 0) + (s.hdg || 0)) % 360 + 360) % 360
    readonly property real distKN: Math.sqrt((s.distN || 0) * (s.distN || 0) + (s.distE || 0) * (s.distE || 0)) / 1000
    readonly property real distTo: (Math.atan2(s.distE || 0, s.distN || 0) * 180 / Math.PI + 360) % 360
    readonly property real sogKn: Theme.knots(Math.sqrt((s.u || 0) * (s.u || 0) + (s.v || 0) * (s.v || 0)))
    readonly property color hdgColor: !s.hdgValid ? Theme.alarm : s.hdgDR ? Theme.warn : Theme.text

    Canvas {
        id: cv
        anchors.fill: parent
        anchors.margins: 6
        onPaint: {
            const g = getContext("2d")
            const W = width, H = height
            g.reset()
            g.fillStyle = Theme.panel; g.fillRect(0, 0, W, H)
            const s = root.s
            if (!s.hasShip) {
                g.fillStyle = Theme.dim; g.font = Theme.cfont(20); g.textAlign = "center"
                g.fillText("Судно не загружено — «Открыть судно…»", W / 2, H / 2)
                return
            }
            const cx = W / 2, cy = H / 2
            // радиус: картушка с подписями градусов не должна заходить под окна в углах
            const LBL = 42                                   // запас на подписи градусов снаружи кольца
            let R = Math.min(W, H) / 2 - 44
            const boxes = [hdgBox, envBox, spdBox, scaleBox]
            for (let i = 0; i < boxes.length; ++i) {
                const b = boxes[i]
                if (!b.visible) continue
                const bx = b.x - cv.x, by = b.y - cv.y
                const nx = Math.max(bx, Math.min(cx, bx + b.width)), ny = Math.max(by, Math.min(cy, by + b.height))
                R = Math.min(R, Math.hypot(nx - cx, ny - cy) - LBL)
            }
            R = Math.max(R, 80)
            const k = R / root.range                 // пикселей на метр
            const c0n = root.followVessel ? s.n : s.refN, c0e = root.followVessel ? s.e : s.refE
            const X = function (e) { return cx + (e - c0e) * k }
            const Y = function (n) { return cy - (n - c0n) * k }
            const pol = function (r, deg) { const a = deg * Math.PI / 180; return [cx + Math.sin(a) * r, cy - Math.cos(a) * r] }
            const angd = function (a, b) { return Math.abs(((a - b) % 360 + 540) % 360 - 180) }
            const halo = function (txt, x, y) {          // текст на подложке цвета панели: не сливается с линиями
                g.lineWidth = 5; g.lineJoin = "round"; g.strokeStyle = Theme.panel; g.strokeText(txt, x, y); g.fillText(txt, x, y)
            }

            // ── нижний слой: кольца, сетка, картушка ──
            g.strokeStyle = Theme.grid; g.lineWidth = 1
            for (let i = 1; i <= 4; ++i) { g.beginPath(); g.arc(cx, cy, R * i / 4, 0, 2 * Math.PI); g.stroke() }
            g.beginPath(); g.moveTo(cx - R, cy); g.lineTo(cx + R, cy); g.moveTo(cx, cy - R); g.lineTo(cx, cy + R); g.stroke()
            g.strokeStyle = Theme.line; g.lineWidth = 2; g.beginPath(); g.arc(cx, cy, R, 0, 2 * Math.PI); g.stroke()
            for (let b = 0; b < 360; b += 5) {
                const len = b % 30 === 0 ? 14 : b % 10 === 0 ? 9 : 5
                const p1 = pol(R, b), p2 = pol(R - len, b)
                g.strokeStyle = b % 30 === 0 ? Theme.dim : Theme.line; g.lineWidth = b % 30 === 0 ? 2 : 1
                g.beginPath(); g.moveTo(p1[0], p1[1]); g.lineTo(p2[0], p2[1]); g.stroke()
            }
            g.textAlign = "center"; g.textBaseline = "middle"
            for (let b = 0; b < 360; b += 30) {
                const p = pol(R + 28, b), main = b % 90 === 0
                g.fillStyle = main ? Theme.text : Theme.dim
                g.font = main ? Theme.cfont(20, true) : Theme.cfont(14, false, true)
                g.fillText(b === 0 ? "С" : b === 90 ? "В" : b === 180 ? "Ю" : b === 270 ? "З" : ("00" + b).slice(-3), p[0], p[1])
            }
            g.textBaseline = "alphabetic"

            // след
            const t = root.track
            if (t.length >= 4) {
                g.strokeStyle = Qt.rgba(0.36, 0.78, 1.0, 0.35); g.lineWidth = 1.5; g.beginPath()
                g.moveTo(X(t[1]), Y(t[0]))
                for (let i = 2; i + 1 < t.length; i += 2) g.lineTo(X(t[i + 1]), Y(t[i]))
                g.stroke()
            }

            // ── судно ──
            const known = !!s.hdgValid
            const L = hull.length || 60, B = hull.beam || 14
            const h = s.hdg * Math.PI / 180, ch = Math.cos(h), sh = Math.sin(h)
            const Pt = function (x, y) {               // x — к носу, y — на правый борт
                const n = s.n + x * ch - y * sh, e = s.e + x * sh + y * ch
                return [X(e), Y(n)]
            }
            const col = !known ? Theme.dim : (s.hdgDR || s.posDR) ? Theme.warn : !s.posValid ? Theme.alarm : Theme.vessel
            const shape = [[L / 2, 0], [L / 2 - B * 0.9, B / 2], [-L / 2, B / 2], [-L / 2, -B / 2], [L / 2 - B * 0.9, -B / 2]]
            // счисление положения: круг вероятного ухода вокруг судна (оценка ядра drDriftM)
            if (s.posDR && s.drDriftM > 0) {
                g.strokeStyle = Theme.warn; g.lineWidth = 2; g.setLineDash([6, 5])
                g.fillStyle = Qt.rgba(0.89, 0.70, 0.24, 0.08)
                g.beginPath(); g.arc(X(s.e), Y(s.n), Math.max(6, s.drDriftM * k), 0, 2 * Math.PI); g.fill(); g.stroke(); g.setLineDash([])
            }
            // курсовая черта от носа до кольца — под корпусом и подписями
            if (known) {
                const bow = Pt(L / 2, 0), far = pol(R - 16, s.hdg)
                g.strokeStyle = col; g.lineWidth = 1.5; g.setLineDash([6, 6])
                g.beginPath(); g.moveTo(bow[0], bow[1]); g.lineTo(far[0], far[1]); g.stroke(); g.setLineDash([])
            }
            const hullPts = shape.map(function (q) { return Pt(q[0], q[1]) })
            g.beginPath()
            for (let i = 0; i < hullPts.length; ++i) { const p = hullPts[i]; if (i === 0) g.moveTo(p[0], p[1]); else g.lineTo(p[0], p[1]) }
            g.closePath()
            g.fillStyle = Qt.rgba(col.r, col.g, col.b, known ? 0.14 : 0.05); g.fill()
            g.strokeStyle = col; g.lineWidth = 2; if (!known) g.setLineDash([7, 6]); g.stroke(); g.setLineDash([])
            // движители: вектор упора (факт), длина ∝ доле упора
            const th = root.thrusters
            for (let i = 0; i < th.length; ++i) {
                const q = th[i], p = Pt(q.x, q.y)
                g.fillStyle = q.failed ? Theme.alarm : q.taken ? Theme.ok : Theme.dim
                g.beginPath(); g.arc(p[0], p[1], 4, 0, 2 * Math.PI); g.fill()
                const pct = q.fb ? q.fbPct : q.cmdPct
                if (known && Math.abs(pct) > 1) {
                    const a = (q.azimuth ? q.fbAng : 90) * Math.PI / 180 + h   // направление силы на судно
                    const len = Math.min(1, Math.abs(pct) / 100) * 46 * (pct < 0 ? -1 : 1)   // пикселей: до 46 при 100 %
                    g.strokeStyle = Theme.fb; g.lineWidth = 2; g.beginPath(); g.moveTo(p[0], p[1])
                    g.lineTo(p[0] + Math.sin(a) * len, p[1] - Math.cos(a) * len); g.stroke()
                }
            }
            // истинное положение в имитаторе (для проверки оценки)
            if (s.sim && s.trueN !== undefined) {
                g.strokeStyle = Theme.dim; g.lineWidth = 1; const tx = X(s.trueE), ty = Y(s.trueN)
                g.beginPath(); g.moveTo(tx - 5, ty - 5); g.lineTo(tx + 5, ty + 5); g.moveTo(tx - 5, ty + 5); g.lineTo(tx + 5, ty - 5); g.stroke()
            }
            // заданная точка — поверх судна
            const rx = X(s.refE), ry = Y(s.refN)
            g.strokeStyle = Theme.accent; g.lineWidth = 2.5
            g.beginPath(); g.moveTo(rx - 12, ry); g.lineTo(rx + 12, ry); g.moveTo(rx, ry - 12); g.lineTo(rx, ry + 12); g.stroke()
            g.beginPath(); g.arc(rx, ry, 6, 0, 2 * Math.PI); g.stroke()

            // подписи колец — верхний слой: на диагонали, дальней от курса, ветра и возмущения; под корпусом пропускаются
            const avoid = [s.hdg, s.hdg + 180]
            if (s.windValid) avoid.push(root.windFromTrue)
            if (root.distKN > 2) avoid.push(root.distTo)
            let ray = 225, best = -1
            const rays = [45, 135, 225, 315]
            for (let i = 0; i < rays.length; ++i) {
                let m = 360
                for (let j = 0; j < avoid.length; ++j) m = Math.min(m, angd(rays[i], avoid[j]))
                if (m > best) { best = m; ray = rays[i] }
            }
            g.fillStyle = Theme.dim; g.font = Theme.cfont(14, false, true)
            const inHull = function (x, y) {          // точка внутри контура судна на экране
                let c = false
                for (let i = 0, j = hullPts.length - 1; i < hullPts.length; j = i++) {
                    const a = hullPts[i], b = hullPts[j]
                    if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) c = !c
                }
                return c
            }
            g.textAlign = "center"; g.textBaseline = "middle"
            for (let i = 1; i <= 4; ++i) {
                const p = pol(R * i / 4, ray)
                if (inHull(p[0], p[1]) || inHull(p[0] - 30, p[1]) || inHull(p[0] + 30, p[1])) continue   // под корпусом не подписываем
                const rv = root.range * i / 4
                halo(Theme.num(rv, Math.abs(rv - Math.round(rv)) < 0.05 ? 0 : 1) + " м", p[0], p[1])
            }
            g.textBaseline = "alphabetic"
            // ── значки на ободе ──
            const tri = function (deg, c, filled, inward) {     // треугольник: вершина на кольце
                const sz = 13, d = inward ? 1 : -1
                const tip = pol(R - 2 * d, deg), l = pol(R + sz * d, deg - 3.5), r = pol(R + sz * d, deg + 3.5)
                g.beginPath(); g.moveTo(tip[0], tip[1]); g.lineTo(l[0], l[1]); g.lineTo(r[0], r[1]); g.closePath()
                g.fillStyle = filled ? c : Theme.panel; g.fill(); g.strokeStyle = c; g.lineWidth = 2; g.stroke()
            }
            tri(s.refHdg, Theme.accent, false, true)              // курс задания — контур снаружи
            if (known) tri(s.hdg, col, true, false)                // курс — заливка внутри
            const rimArrow = function (deg, c, inward) {           // стрелка у обода: ветер — к центру (откуда), возмущение — наружу (куда)
                const a = pol(R - 4, deg), b = pol(R - 36, deg)
                const from = inward ? a : b, to = inward ? b : a
                g.strokeStyle = c; g.fillStyle = c; g.lineWidth = 3
                g.beginPath(); g.moveTo(from[0], from[1]); g.lineTo(to[0], to[1]); g.stroke()
                const ang = Math.atan2(to[1] - from[1], to[0] - from[0])
                g.beginPath(); g.moveTo(to[0], to[1])
                g.lineTo(to[0] - 11 * Math.cos(ang - 0.45), to[1] - 11 * Math.sin(ang - 0.45))
                g.lineTo(to[0] - 11 * Math.cos(ang + 0.45), to[1] - 11 * Math.sin(ang + 0.45)); g.closePath(); g.fill()
            }
            if (s.windValid) rimArrow(root.windFromTrue, Theme.wind, true)
            if (root.distKN > 2) rimArrow(root.distTo, Theme.dist, false)

            // состояние курса — под центром, на подложке, ниже кормы
            if (!known) {
                g.fillStyle = Theme.alarm; g.font = Theme.cfont(16, true); g.textAlign = "center"
                halo("курс неизвестен", cx, cy + R * 0.8)
            } else if (s.posDR) {
                g.fillStyle = Theme.warn; g.font = Theme.cfont(16, true); g.textAlign = "center"
                halo("счисление " + Theme.mmss(s.refLostS) + " · уход до " + Theme.num(s.drDriftM || 0, 1) + " м", cx, cy + R * 0.8)
            }
        }
    }
    onSChanged: cv.requestPaint()
    onRangeChanged: cv.requestPaint()
    onFollowVesselChanged: cv.requestPaint()
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()

    // ── окна по углам: цифры отдельно от графики ──
    component Box: Rectangle {
        color: Theme.panel2; radius: 3; border.color: Theme.line; border.width: 1
    }
    component Cap: Label { color: Theme.dim; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.2 }

    Box {
        id: hdgBox
        visible: !!root.s.hasShip
        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 10
        width: 168; height: 78
        border.color: !root.s.hdgValid ? Theme.alarm : root.s.hdgDR ? Theme.warn : Theme.line
        border.width: root.s.hdgValid && !root.s.hdgDR ? 1 : 2
        Cap { x: 10; y: 6; text: "КУРС" }
        Label {
            anchors.right: parent.right; anchors.rightMargin: 10; y: 6
            text: !root.s.hdgValid ? "НЕТ" : root.s.hdgDR ? "СЧИСЛ." : "гиро"
            color: root.hdgColor; font.pixelSize: 12; font.bold: true
        }
        Label {
            x: 10; y: 26
            text: root.s.hdgValid ? Theme.hdg3(root.s.hdg) : "— — —"
            color: root.hdgColor; font.pixelSize: 34; font.family: Theme.mono
        }
    }

    Box {
        id: envBox
        visible: !!root.s.hasShip
        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
        width: 196; height: 78
        Column {
            x: 10; y: 6; spacing: 1; width: parent.width - 20
            Row {
                spacing: 6
                Rectangle { width: 14; height: 3; radius: 1; color: Theme.wind; anchors.verticalCenter: parent.verticalCenter }
                Label {
                    text: root.s.windValid ? "Ветер " + Theme.bearing(root.windFromTrue) + " · " + Theme.num(Theme.knots(root.s.windSpeed), 1) + " уз" : "Ветер: нет данных"
                    color: root.s.windValid ? Theme.wind : Theme.dim; font.pixelSize: 13; font.family: Theme.mono
                }
            }
            Label {
                leftPadding: 20; visible: !!root.s.windValid
                text: "(" + Theme.num(root.s.windSpeed, 1) + " м/с, откуда)"; color: Theme.dim; font.pixelSize: 12
            }
            Row {
                spacing: 6
                Rectangle { width: 14; height: 3; radius: 1; color: Theme.dist; anchors.verticalCenter: parent.verticalCenter }
                Label {
                    text: "Возм. → " + Theme.bearing(root.distTo) + " · " + Theme.num(root.distKN, 0) + " кН"
                    color: Theme.dist; font.pixelSize: 13; font.family: Theme.mono
                }
            }
        }
    }

    Box {
        id: spdBox
        visible: !!root.s.hasShip
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 10
        width: 168; height: 78
        Cap { x: 10; y: 6; text: "СКОРОСТЬ" }
        Label { x: 10; y: 24; text: Theme.num(root.sogKn, 2) + " уз"; color: Theme.text; font.pixelSize: 22; font.family: Theme.mono }
        Label {
            x: 10; y: 52
            text: (root.s.rot > 0 ? "+" : "") + Theme.num(root.s.rot, 1) + " °/мин"
            color: Math.abs(root.s.rot || 0) > 3 ? Theme.warn : Theme.text; font.pixelSize: 15; font.family: Theme.mono
        }
    }

    Box {
        id: scaleBox
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 10
        width: 232; height: 78
        Cap { x: 10; y: 6; text: "МАСШТАБ, М" }
        Row {
            x: 8; y: 22; spacing: 3
            Repeater {
                model: [10, 25, 50, 100, 250]
                delegate: Rectangle {          // свои кнопки: стандартные обрезали «100» и «250»
                    readonly property bool on: root.range === modelData
                    width: 41; height: 26; radius: 3
                    color: on ? Theme.accent : Theme.panel; border.color: on ? Theme.accent : Theme.line
                    Label { anchors.centerIn: parent; text: modelData; font.pixelSize: 13; font.family: Theme.mono; color: parent.on ? Theme.bg : Theme.text }
                    TapHandler { onTapped: root.range = modelData }
                }
            }
        }
        Row {
            x: 4; y: 50; spacing: 2
            CheckBox { text: "За судном"; checked: root.followVessel; onToggled: root.followVessel = checked; font.pixelSize: 12; implicitHeight: 26 }
            Button { text: "Обозначения"; flat: true; checkable: true; checked: root.showLegend; onToggled: root.showLegend = checked; font.pixelSize: 12; implicitHeight: 26 }
        }
    }

    // обозначения — по кнопке, не занимают место постоянно
    Box {
        visible: root.showLegend
        anchors.right: scaleBox.right; anchors.bottom: scaleBox.top; anchors.bottomMargin: 6
        width: legendCol.implicitWidth + 20; height: legendCol.implicitHeight + 16
        Column {
            id: legendCol
            x: 10; y: 8; spacing: 2
            Repeater {
                model: [["＋", Theme.accent, "заданная точка"], ["▽", Theme.accent, "курс задания (на ободе)"],
                        ["▲", Theme.vessel, "курс судна (на ободе)"], ["▭", Theme.vessel, "судно по оценке ядра"],
                        ["×", Theme.dim, "истинное положение (имитатор)"], ["→", Theme.wind, "ветер, откуда (к центру)"],
                        ["→", Theme.dist, "внешнее возмущение, куда (наружу)"]]
                delegate: Row {
                    spacing: 6
                    Label { text: modelData[0]; color: modelData[1]; font.pixelSize: Theme.fsSmall; width: 14 }
                    Label { text: modelData[2]; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                }
            }
        }
    }
}
