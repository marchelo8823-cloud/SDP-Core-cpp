// План положения: север вверх, в центре — заданная точка. Вокруг — круг с градусами: белый треугольник — курс судна,
// синий контур — заданный курс. Судно по оценке ядра, след, точка задания, движители с векторами упора,
// ветер и внешнее возмущение (оба — откуда) стрелками у обода. При счислении — круг вероятного ухода.
// Правило слоёв: графика (кольца, картушка, судно) — нижний слой; цифры — в окнах по углам панели, на плане только значки.
// Подписи колец — на диагонали, свободной от курса, ветра и возмущения, на подложке; под корпусом не ставятся.
import QtQuick
import QtQuick.Controls
import "."

Rectangle {
    id: root
    color: Theme.plot
    radius: 6
    property var s: ({})
    property var hull: ({})
    property var thrusters: []
    property var track: []
    property real range: 50          // м — радиус внешнего кольца
    property bool followVessel: false
    property bool showLegend: false

    readonly property real windFromTrue: (((s.windFromRel || 0) + (s.hdg || 0)) % 360 + 360) % 360
    readonly property real distKN: Math.sqrt((s.distN || 0) * (s.distN || 0) + (s.distE || 0) * (s.distE || 0)) / 1000
    readonly property real distFrom: (Math.atan2(s.distE || 0, s.distN || 0) * 180 / Math.PI + 180 + 360) % 360   // откуда, как и ветер
    readonly property real sogKn: Theme.knots(Math.sqrt((s.u || 0) * (s.u || 0) + (s.v || 0) * (s.v || 0)))
    readonly property color hdgColor: !s.hdgValid ? Theme.alarm : s.hdgDR ? Theme.warn : Theme.text
    readonly property bool roomy: width >= 520 && height >= 420                       // окна по углам — только если есть место

    Canvas {
        id: cv
        anchors.fill: parent
        anchors.margins: 6
        onPaint: {
            const g = getContext("2d")
            const W = width, H = height
            g.reset()
            g.fillStyle = Theme.plot; g.fillRect(0, 0, W, H)
            const s = root.s
            if (!s.hasShip) {
                g.fillStyle = Theme.dim; g.font = "20px '" + Theme.font + "'"; g.textAlign = "center"
                g.fillText("Судно не загружено — «Судно…»", W / 2, H / 2)
                return
            }
            const cx = W / 2, cy = H / 2
            // радиус: место снаружи — под круг с градусами (подписи на R + 38); круг не заходит под окна в углах
            let R = Math.min(W, H) / 2 - 62
            const boxes = [hdgBox, envBox, spdBox, scaleBox]
            for (let i = 0; i < boxes.length; ++i) {
                const b = boxes[i]
                if (!b.visible) continue
                const bx = b.x - cv.x, by = b.y - cv.y
                const nx = Math.max(bx, Math.min(cx, bx + b.width)), ny = Math.max(by, Math.min(cy, by + b.height))
                R = Math.min(R, Math.hypot(nx - cx, ny - cy) - 50)
            }
            if (R < 40) return                       // окно ещё не разложено или слишком мало
            const k = R / root.range                 // пикселей на метр
            const c0n = root.followVessel ? s.n : s.refN, c0e = root.followVessel ? s.e : s.refE
            const X = function (e) { return cx + (e - c0e) * k }
            const Y = function (n) { return cy - (n - c0n) * k }
            const PR = function (deg, r) { const a = deg * Math.PI / 180; return [cx + Math.sin(a) * r, cy - Math.cos(a) * r] }
            const halo = function (txt, x, y) {      // текст на подложке цвета плана: не сливается с линиями
                g.lineWidth = 5; g.lineJoin = "round"; g.strokeStyle = Theme.plot; g.strokeText(txt, x, y); g.fillText(txt, x, y)
            }
            // кольца дальности и сетка — нижний слой
            g.strokeStyle = Theme.line; g.lineWidth = 1
            for (let i = 1; i <= 4; ++i) { g.beginPath(); g.arc(cx, cy, R * i / 4, 0, 2 * Math.PI); g.stroke() }
            g.beginPath(); g.moveTo(cx - R, cy); g.lineTo(cx + R, cy); g.moveTo(cx, cy - R); g.lineTo(cx, cy + R); g.stroke()
            // круг с градусами: штрихи через 5°, длинные через 30°, подписи через 30°, С/В/Ю/З
            g.strokeStyle = Theme.btnLine; g.lineWidth = 1.5; g.beginPath(); g.arc(cx, cy, R, 0, 2 * Math.PI); g.stroke()
            for (let d = 0; d < 360; d += 5) {
                const big = d % 30 === 0, r2 = R + (big ? 20 : d % 10 === 0 ? 13 : 8)
                const a = PR(d, R), b = PR(d, r2)
                g.strokeStyle = big ? "#c9d4de" : "#6b7c8d"; g.lineWidth = big ? 2 : 1.2
                g.beginPath(); g.moveTo(a[0], a[1]); g.lineTo(b[0], b[1]); g.stroke()
            }
            g.textAlign = "center"; g.textBaseline = "middle"
            const card = { 0: "С", 90: "В", 180: "Ю", 270: "З" }
            for (let d = 0; d < 360; d += 30) {
                const p = PR(d, R + 38)
                if (card[d]) { g.fillStyle = Theme.text; g.font = "bold 17px '" + Theme.font + "'"; g.fillText(card[d], p[0], p[1]) }
                else { g.fillStyle = Theme.dim; g.font = "13px '" + Theme.mono + "'"; g.fillText(("00" + d).slice(-3), p[0], p[1]) }
            }
            g.textBaseline = "alphabetic"
            const tri = function (deg, r0, r1, w, fill, col) {
                const a = PR(deg, r0), b = PR(deg - w, r1), c = PR(deg + w, r1)
                g.beginPath(); g.moveTo(a[0], a[1]); g.lineTo(b[0], b[1]); g.lineTo(c[0], c[1]); g.closePath()
                if (fill) { g.fillStyle = col; g.fill() } else { g.strokeStyle = col; g.lineWidth = 2; g.stroke() }
            }
            const known = !!s.hdgValid
            if (known) tri(s.hdg, R, R - 16, 2.6, true, s.hdgDR ? Theme.warn : Theme.text)        // курс судна
            if (s.active) tri(s.opValid ? s.spHdg : s.refHdg, R + 22, R + 36, 2.2, false, Theme.accent)   // заданный курс оператора (как в панели «Курс»)
            // след
            const t = root.track
            if (t.length >= 4) {
                g.strokeStyle = Qt.rgba(0.49, 0.76, 0.93, 0.45); g.lineWidth = 1.5; g.beginPath()
                g.moveTo(X(t[1]), Y(t[0]))
                for (let i = 2; i + 1 < t.length; i += 2) g.lineTo(X(t[i + 1]), Y(t[i]))
                g.stroke()
            }
            // при счислении положения — круг вероятного ухода вокруг оценки
            if (s.posDR && s.drDriftM > 0.2) {
                g.strokeStyle = Theme.warn; g.fillStyle = Theme.tint(Theme.warn, 0.10); g.lineWidth = 2; g.setLineDash([8, 6])
                g.beginPath(); g.arc(X(s.e), Y(s.n), s.drDriftM * k, 0, 2 * Math.PI); g.fill(); g.stroke(); g.setLineDash([])
            }
            // судно
            const L = hull.length || 60, B = hull.beam || 14
            const h = s.hdg * Math.PI / 180, ch = Math.cos(h), sh = Math.sin(h)
            const P = function (x, y) { return [X(s.e + x * sh + y * ch), Y(s.n + x * ch - y * sh)] }   // x — к носу, y — на правый борт
            const shape = [[L / 2, 0], [L / 2 - B * 0.9, B / 2], [-L / 2, B / 2], [-L / 2, -B / 2], [L / 2 - B * 0.9, -B / 2]]
            const hullPts = shape.map(function (q) { return P(q[0], q[1]) })
            // курсовая черта: от носа до кольца, не дальше — не перечёркивает подписи картушки
            if (known) {
                const bow = P(L / 2, 0), far = PR(s.hdg, R - 18)
                g.strokeStyle = s.hdgDR ? Theme.warn : Theme.vessel; g.lineWidth = 1.5; g.setLineDash([6, 6])
                g.beginPath(); g.moveTo(bow[0], bow[1]); g.lineTo(far[0], far[1]); g.stroke(); g.setLineDash([])
            }
            g.beginPath()
            for (let i = 0; i < hullPts.length; ++i) { const p = hullPts[i]; if (i === 0) g.moveTo(p[0], p[1]); else g.lineTo(p[0], p[1]) }
            g.closePath()
            // нет курса — судно серым пунктиром: направление корпуса на экране — последнее известное, а не истинное
            g.fillStyle = !known ? Theme.tint(Theme.off, 0.10) : s.posValid ? Qt.rgba(0.49, 0.76, 0.93, 0.22) : Qt.rgba(0.9, 0.33, 0.29, 0.25)
            g.fill(); g.strokeStyle = !known ? Theme.off : s.posDR ? Theme.warn : Theme.vessel; g.lineWidth = 2
            if (!known) g.setLineDash([7, 6]); g.stroke(); g.setLineDash([])
            // движители: вектор упора (факт), длина ∝ доле упора
            const th = root.thrusters
            for (let i = 0; i < th.length; ++i) {
                const q = th[i], p = P(q.x, q.y)
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
            // ветер и внешнее возмущение (оба — откуда) — стрелки у обода, без подписей: цифры в окне справа вверху
            const arrow = function (deg, col, r0) {
                const o = PR(deg, R - r0), i2 = PR(deg, R - r0 - 40)
                g.strokeStyle = col; g.fillStyle = col; g.lineWidth = 3
                g.beginPath(); g.moveTo(o[0], o[1]); g.lineTo(i2[0], i2[1]); g.stroke()
                const a2 = Math.atan2(i2[1] - o[1], i2[0] - o[0])
                g.beginPath(); g.moveTo(i2[0], i2[1]); g.lineTo(i2[0] - 12 * Math.cos(a2 - 0.4), i2[1] - 12 * Math.sin(a2 - 0.4)); g.lineTo(i2[0] - 12 * Math.cos(a2 + 0.4), i2[1] - 12 * Math.sin(a2 + 0.4)); g.closePath(); g.fill()
            }
            if (s.windValid) arrow(root.windFromTrue, Theme.wind, 20)
            if (root.distKN > 2) arrow(root.distFrom, Theme.dist, 66)
            // подписи колец — верхний слой: диагональ, дальняя от курса, ветра и возмущения; под корпусом пропускаются
            const angd = function (a, b) { return Math.abs(((a - b) % 360 + 540) % 360 - 180) }
            const avoid = known ? [s.hdg, s.hdg + 180] : []
            if (s.windValid) avoid.push(root.windFromTrue)
            if (root.distKN > 2) avoid.push(root.distFrom)
            let lb = 45, best = -1
            for (let j = 0; j < 4; ++j) {
                const c = 45 + j * 90; let m = 360
                for (let q = 0; q < avoid.length; ++q) m = Math.min(m, angd(c, avoid[q]))
                if (m > best + 1e-6) { best = m; lb = c }
            }
            const inHull = function (x, y) {
                let c = false
                for (let i = 0, j = hullPts.length - 1; i < hullPts.length; j = i++) {
                    const a = hullPts[i], b = hullPts[j]
                    if ((a[1] > y) !== (b[1] > y) && x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0]) c = !c
                }
                return c
            }
            g.fillStyle = Theme.dim; g.font = "13px '" + Theme.mono + "'"; g.textAlign = "center"; g.textBaseline = "middle"
            for (let i = 1; i <= 4; ++i) {
                const p = PR(lb, R * i / 4), rv = root.range * i / 4
                if (inHull(p[0], p[1]) || inHull(p[0] - 30, p[1]) || inHull(p[0] + 30, p[1])) continue
                halo(Theme.num(rv, Math.abs(rv - Math.round(rv)) < 0.05 ? 0 : 1) + " м", p[0], p[1])   // 12,5 м, а не «13 м»
            }
            // состояние под центром — на подложке, ниже кормы
            g.font = "bold 15px '" + Theme.font + "'"
            if (!known) { g.fillStyle = Theme.alarm; halo("курс неизвестен", cx, cy + R * 0.8) }
            else if (s.posDR && s.drDriftM > 0.2) { g.fillStyle = Theme.warn; halo("вероятный уход до " + Theme.num(s.drDriftM, s.drDriftM < 10 ? 1 : 0) + " м", cx, cy + R * 0.8) }
            g.textBaseline = "alphabetic"
        }
    }
    onSChanged: cv.requestPaint()
    onRangeChanged: cv.requestPaint()
    onFollowVesselChanged: cv.requestPaint()
    onWidthChanged: cv.requestPaint()
    onHeightChanged: cv.requestPaint()

    // ── окна по углам: цифры отдельно от графики ──
    component Box: Rectangle { color: Theme.panel2; radius: 4; border.color: Theme.line; border.width: 1 }
    component Cap: Label { color: Theme.dim; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.2 }

    Box {
        id: hdgBox
        visible: !!root.s.hasShip && root.roomy
        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 10
        width: 150; height: 70
        border.color: !root.s.hdgValid ? Theme.alarm : root.s.hdgDR ? Theme.warn : Theme.line
        border.width: root.s.hdgValid && !root.s.hdgDR ? 1 : 2
        Cap { x: 10; y: 6; text: "КУРС" }
        Label {
            anchors.right: parent.right; anchors.rightMargin: 10; y: 5
            text: !root.s.hdgValid ? "НЕТ" : root.s.hdgDR ? "СЧИСЛ." : "гиро"
            color: root.hdgColor; font.pixelSize: 11; font.bold: true
        }
        Label {
            x: 10; y: 22
            text: root.s.hdgValid ? Theme.hdg3(root.s.hdg) : "— — —"
            color: root.hdgColor; font.pixelSize: 30; font.family: Theme.mono
        }
    }

    Box {
        id: envBox
        visible: !!root.s.hasShip && root.roomy
        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
        width: 190; height: 70
        Column {
            x: 10; y: 6; spacing: 1
            Row {
                spacing: 6
                Rectangle { width: 14; height: 3; radius: 1; color: Theme.wind; anchors.verticalCenter: parent.verticalCenter }
                Label {
                    text: root.s.windValid ? "Ветер " + Theme.bearing(root.windFromTrue) + " · " + Theme.num(Theme.knots(root.s.windSpeed), 1) + " уз" : "Ветер: нет данных"
                    color: root.s.windValid ? Theme.wind : Theme.dim; font.pixelSize: 13; font.family: Theme.mono
                }
            }
            Label { leftPadding: 20; visible: !!root.s.windValid; text: "(" + Theme.num(root.s.windSpeed, 1) + " м/с, откуда)"; color: Theme.dim; font.pixelSize: 11 }
            Row {
                spacing: 6
                Rectangle { width: 14; height: 3; radius: 1; color: Theme.dist; anchors.verticalCenter: parent.verticalCenter }
                Label { text: "Возм. " + Theme.bearing(root.distFrom) + " · " + Theme.num(root.distKN, 0) + " кН"; color: Theme.dist; font.pixelSize: 13; font.family: Theme.mono }
            }
        }
    }

    Box {
        id: spdBox
        visible: !!root.s.hasShip && root.roomy
        anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: 10
        width: 150; height: 70
        Cap { x: 10; y: 6; text: "СКОРОСТЬ" }
        Label { x: 10; y: 21; text: Theme.num(root.sogKn, 2) + " уз"; color: Theme.text; font.pixelSize: 20; font.family: Theme.mono }
        Label {
            x: 10; y: 46
            text: (root.s.rot > 0.05 ? "+" : "") + Theme.num(root.s.rot, 1) + " °/мин"
            color: Math.abs(root.s.rot || 0) > 3 ? Theme.warn : Theme.text; font.pixelSize: 14; font.family: Theme.mono
        }
    }

    // масштаб: в углу окном, а в тесной ячейке — строкой внизу (как раньше)
    Box {
        id: scaleBox
        anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 10
        width: 226; height: 70
        Cap { x: 10; y: 6; text: "МАСШТАБ, М" }
        Row {
            x: 8; y: 20; spacing: 3
            Repeater {
                model: [10, 25, 50, 100, 250]
                delegate: Rectangle {          // свои кнопки: стандартные обрезали «100» и «250» и наезжали на «Ю»
                    readonly property bool on: root.range === modelData
                    width: 40; height: 24; radius: 3
                    color: on ? Theme.accent : Theme.panel; border.color: on ? Theme.accent : Theme.btnLine
                    Label { anchors.centerIn: parent; text: modelData; font.pixelSize: 12; font.family: Theme.mono; color: parent.on ? Theme.bg : Theme.text }
                    TapHandler { onTapped: root.range = modelData }
                }
            }
        }
        Row {
            x: 4; y: 45; spacing: 2
            CheckBox { text: "За судном"; checked: root.followVessel; onToggled: root.followVessel = checked; font.pixelSize: 11; implicitHeight: 22 }
            Button { text: "Обозначения"; flat: true; checkable: true; checked: root.showLegend; onToggled: root.showLegend = checked; font.pixelSize: 11; implicitHeight: 22 }
        }
    }

    // обозначения — по кнопке, а не постоянно в углу
    Box {
        visible: root.showLegend
        anchors.right: scaleBox.right; anchors.bottom: scaleBox.top; anchors.bottomMargin: 6
        width: legendCol.implicitWidth + 20; height: legendCol.implicitHeight + 16
        Column {
            id: legendCol
            x: 10; y: 8; spacing: 2
            Repeater {
                model: {
                    const m = [["＋", Theme.accent, "заданная точка"], ["▽", Theme.accent, "заданный курс (снаружи круга)"],
                               ["▲", Theme.text, "курс судна (внутри круга)"], ["▭", Theme.vessel, "судно (оценка ядра)"]]
                    if (root.s.sim) m.push(["×", Theme.dim, "истинное положение (имитатор)"])
                    m.push(["→", Theme.wind, "ветер, откуда"]); m.push(["→", Theme.dist, "внешнее возмущение, откуда"])
                    return m
                }
                delegate: Row {
                    spacing: 6
                    Label { text: modelData[0]; color: modelData[1]; font.pixelSize: Theme.fsSmall; width: 14 }
                    Label { text: modelData[2]; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                }
            }
        }
    }
}
