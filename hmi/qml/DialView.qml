import QtQuick
import QtQuick.Controls
import Sdp

// Круговой вид «судно в центре» с поворотом судна: курс выбирается перетаскиванием по кольцу компаса
// или кнопками ±1°/±10°, команда уходит только после «Принять». Команда «hdg» идёт тем же путём, что и блок «Уставка».
// Встраивается в любую область рабочего стола. В маленькой области жест отключён (compact), чтобы не повернуть судно случайно.
Item {
    id: pg
    clip: true
    readonly property var st: backend.s
    readonly property var be: backend
    property bool underlayOn: true       // карта и градусная сетка под кругом
    property color mapBg: Theme.bg      // фон карты под кругом: тёмный, чтобы подписи и векторы читались в любой палитре
    property bool graticuleOn: true
    property real mapOpacity: 0.8
    signal openMapSettings()
    readonly property bool compact: width < 380 || height < 330
    readonly property bool modeOn: st.mode !== 0 && st.mode !== 1
    readonly property real psi: st.psi === undefined ? 0 : st.psi
    property bool rotating: false
    property bool dragging: false
    property real tgt: 0
    // центр вращения (м от миделя: вдоль + к носу, поперёк + к правому борту), хранится в настройках поста
    readonly property real pivotX: Number(st.pivotX || 0)
    readonly property real pivotY: Number(st.pivotY || 0)
    readonly property bool pivotOff: Math.abs(pivotX) > 0.05 || Math.abs(pivotY) > 0.05
    // перемещение точки удержания мышью
    property bool trailOn: true                             // след судна (настройка «Вид»)
    property bool moving: false
    property bool moveDrag: false
    property real mvN: 0
    property real mvE: 0
    readonly property real kIn: 0.90                       // радиус круга отклонений как доля наружного радиуса кольца
    property string sentText: ""
    readonly property real delta: (((tgt - psi + 540) % 360) + 360) % 360 - 180

    readonly property var ranges: [2, 5, 10, 20, 50, 100, 200, 500, 1000]
    property int rangeIdx: -1
    readonly property real autoRange: {
        var need = Math.max((st.errDist || 0) * 1.25, 2)
        for (var i = 0; i < ranges.length; ++i) if (ranges[i] >= need) return ranges[i]
        return ranges[ranges.length - 1]
    }
    readonly property real range: rangeIdx >= 0 ? ranges[rangeIdx] : autoRange

    function norm(a) { return ((a % 360) + 360) % 360 }
    function setTarget(a) { if (compact) return; tgt = norm(Math.round(a)); rotating = true; moving = false; backend.proposeCancel() }
    function cancel() { rotating = false; dragging = false; moving = false; moveDrag = false; backend.proposeCancel() }
    // смещение точки тела (x вдоль, y поперёк) в мировых осях (север, восток) при курсе h
    function bodyToNE(x, y, h) { var a = h * Math.PI / 180; return [x * Math.cos(a) - y * Math.sin(a), x * Math.sin(a) + y * Math.cos(a)] }
    // где окажется точка удержания, если повернуть судно вокруг центра вращения на курс h
    function spForHeading(h) {
        var o = bodyToNE(pivotX, pivotY, st.spPsi || 0), w = bodyToNE(pivotX, pivotY, h)
        return [(st.spN || 0) + o[0] - w[0], (st.spE || 0) + o[1] - w[1]]
    }
    readonly property var rotSp: spForHeading(tgt)
    readonly property real rotShift: Math.hypot(rotSp[0] - (st.spN || 0), rotSp[1] - (st.spE || 0))
    function pivotName() {
        if (!pivotOff) return "мидель"
        return "вдоль " + (pivotX > 0 ? "+" : "") + pivotX.toFixed(1) + " м, поперёк " + (pivotY > 0 ? "+" : "") + pivotY.toFixed(1) + " м"
    }
    function setMoveFromPixel(mx, my) {
        var ri = dial.rOut * kIn, sc = ri / range
        var dE = (mx - dial.cx) / sc, dN = -(my - dial.cy) / sc, d = Math.hypot(dN, dE)
        if (d > range) { dN *= range / d; dE *= range / d }
        rotating = false; backend.propose((st.n || 0) + dN, (st.e || 0) + dE, -1)
    }
    // начало общих векторов (смещение, скорость, сила): центр вращения на судне, в пикселях от центра циркуля
    function pivotOffsetPx(sc) { var o = bodyToNE(pivotX, pivotY, psi); return [o[1] * sc, -o[0] * sc] }
    function spPixel() {
        var ri = dial.rOut * kIn, sc = ri / range
        var dN = (st.spN || 0) - (st.n || 0), dE = (st.spE || 0) - (st.e || 0), d = Math.hypot(dN, dE)
        var k = d * sc > ri ? ri / d : sc
        return [dial.cx + dE * k, dial.cy - dN * k]
    }
    function acceptMove() {
        if (!st.canControl) return
        sentText = "Команда отправлена: точка N " + Theme.f(mvN, 1) + "  E " + Theme.f(mvE, 1) + " м"
        backend.proposeAccept()
        moving = false; moveDrag = false
        sentTimer.restart()
    }
    function accept() {
        if (!st.canControl) return
        backend.command("hdg " + Math.round(tgt))
        sentText = "Команда отправлена: курс " + Theme.hdg(tgt) + (pivotOff ? " (центр вращения: " + pivotName() + ")" : "")
        rotating = false; dragging = false
        sentTimer.restart()
    }
    function col(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    // антенны систем положения: ромбы в масштабе силуэта по заданным смещениям, цвет по состоянию (как на плане)
    property bool showSensors: true
    // какие векторы показывать: курс, сила (запрос регулятора и упор движителей), смещение (до уставки и скорость); хранится на этом посту
    function flag(k, d) { var v = backend.setting(k, d); return v === true || v === "true" }
    // две группы: g — заданные (зелёные), y — текущие (жёлтые); в каждой можно включать курс, силу, смещение и движители отдельно
    property bool gHdg: flag("vecGHdg", false)
    property bool gForce: flag("vecGForce", true)
    property bool gDisp: flag("vecGDisp", true)
    property bool gThr: flag("vecGThr", false)
    property bool yHdg: flag("vecYHdg", false)
    property bool yForce: flag("vecYForce", true)
    property bool yDisp: flag("vecYDisp", true)
    property bool yThr: flag("vecYThr", true)
    function setFlag(k, v) { backend.setSetting(k, v); dial.requestPaint() }
    readonly property real vLook: 30                  // секунд движения для вектора скорости
    // вектор скорости: сглаживание (постоянная 8 с) и порог показа с гистерезисом — шум датчиков не должен давать «прыгающую» стрелку
    property real smVn: 0
    property real smVe: 0
    property bool velShown: false
    property double velT: 0
    readonly property real velOn: 0.035
    readonly property real velOff: 0.025
    function velStep() {
        var now = Date.now(), dt = velT > 0 ? Math.min(5, (now - velT) / 1000) : 0; velT = now
        var a = dt > 0 ? 1 - Math.exp(-dt / 8) : 1
        smVn += a * ((st.vn || 0) - smVn); smVe += a * ((st.ve || 0) - smVe)
        var sp = Math.hypot(smVn, smVe)
        velShown = velShown ? sp > velOff : sp > velOn
    }
    function stateColor(c) {
        var s = c.state
        if (s === "OK") return c.age >= 0 && c.age < 5 ? Theme.ok : Theme.sub
        if (s === "MONITOR") return Theme.accent
        if (s === "PRED" || s === "MEDIANW") return Theme.warn
        if (s === "MEDIAN" || s === "JUMP") return Theme.bad
        return Theme.sub
    }
    function drawAntennas(ctx, B, L) {
        if (!showSensors) return
        var list = backend.chans || [], len = Math.max(1, st.length || 60), bm = Math.max(1, st.beam || 14)
        var placed = []
        ctx.font = Theme.px(11) + "px sans-serif"; ctx.textBaseline = "middle"
        for (var i = 0; i < list.length; ++i) {
            var c = list[i]; if (!c.isPos) continue
            var ax = c.oy / bm * B, ay = -c.ox / len * L, r = 5, color = stateColor(c)
            ctx.strokeStyle = color; ctx.fillStyle = color; ctx.lineWidth = 2
            ctx.beginPath(); ctx.moveTo(ax, ay - r); ctx.lineTo(ax + r, ay); ctx.lineTo(ax, ay + r); ctx.lineTo(ax - r, ay); ctx.closePath(); ctx.stroke()
            // подпись без поворота силуэта: считаем в экранных осях, поэтому рисуем её после возврата поворота
            placed.push({ x: ax, y: ay, t: c.id + " " + c.state, left: c.oy < 0, color: color })
        }
        ctx.save(); ctx.rotate(-pg.psi * Math.PI / 180)      // подписи всегда горизонтально
        var rects = []
        for (var j = 0; j < placed.length; ++j) {
            var q = placed[j], a = pg.psi * Math.PI / 180
            var sx = q.x * Math.cos(a) - q.y * Math.sin(a), sy = q.x * Math.sin(a) + q.y * Math.cos(a)
            var w = ctx.measureText(q.t).width, h = Theme.px(13)
            var x0 = q.left ? sx - 9 - w : sx + 9, y0 = sy - h / 2
            for (var k = 0; k < 12; ++k) {
                var hit = false
                for (var m = 0; m < rects.length; ++m) { var o = rects[m]; if (x0 < o.x + o.w && x0 + w > o.x && y0 < o.y + o.h && y0 + h > o.y) { y0 = o.y + o.h; hit = true; break } }
                if (!hit) break
            }
            rects.push({ x: x0, y: y0, w: w, h: h })
            ctx.fillStyle = q.color; ctx.textAlign = "left"; ctx.fillText(q.t, x0, y0 + h / 2)
        }
        ctx.restore()
    }

    Connections { target: Theme; function onPresetChanged() { dial.requestPaint() } }
    Timer { id: sentTimer; interval: 4000; onTriggered: pg.sentText = "" }
    Connections { target: backend; function onUpdated() { pg.velStep(); if (pg.visible) dial.requestPaint() } }
    Connections { target: backend; function onHullChanged() { dial.requestPaint() } }
    // новая точка уставки общая с панелью «Уставка»: её можно задать стрелками, мышью на круге или вводом чисел
    Connections { target: backend; function onPropChanged() { pg.moving = backend.propOn; if (backend.propOn) { pg.mvN = backend.propN; pg.mvE = backend.propE; pg.rotating = false } dial.requestPaint() } }
    onTgtChanged: dial.requestPaint()
    onRotatingChanged: dial.requestPaint()
    onMovingChanged: dial.requestPaint()
    onMvNChanged: dial.requestPaint()
    onMvEChanged: dial.requestPaint()
    onPivotXChanged: dial.requestPaint()
    onPivotYChanged: dial.requestPaint()
    onRangeChanged: dial.requestPaint()
    onCompactChanged: if (compact) cancel()
    onWidthChanged: dial.requestPaint()
    onHeightChanged: dial.requestPaint()

    MapUnderlay {
        id: mu
        anchors.fill: parent
        centerX: pg.width / 2; centerY: dialBox.height / 2
        backend: pg.be
        range: pg.range
        plotRadius: (dialBox.side / 2 - 26) * pg.kIn       // тот же круг отклонений, что рисует Canvas ниже
        showMap: pg.underlayOn; showGraticule: pg.graticuleOn; mapOpacity: pg.mapOpacity
        cBg: pg.mapBg; cGrid: Qt.rgba(Theme.sub.r, Theme.sub.g, Theme.sub.b, 0.6); cText: Theme.text
        dim: Theme.preset === 0 ? 0.25 : 0.5
        fontPx: Theme.px(11)
    }
    Item {
        id: dialBox
        anchors { fill: parent; bottomMargin: pg.compact ? 0 : (pg.panelOn ? pg.panelH + Theme.px(4) : rangeRow.height + Theme.px(6)) }
        readonly property real side: Math.min(width, height)
        Canvas {
            id: dial
            width: dialBox.side; height: dialBox.side
            anchors.centerIn: parent
            readonly property real cx: width / 2
            readonly property real cy: height / 2
            readonly property real rOut: width / 2 - 26          // наружный радиус кольца компаса
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                var Ri = rOut * pg.kIn                              // радиус области отклонений
                function P(r, th) { var a = th * Math.PI / 180; return [cx + r * Math.sin(a), cy - r * Math.cos(a)] }
                function arcAt(r, a0, a1) { ctx.arc(cx, cy, r, (a0 - 90) * Math.PI / 180, (a1 - 90) * Math.PI / 180, false) }

                // полоса кольца
                ctx.lineWidth = rOut * 0.10
                ctx.strokeStyle = pg.col(Theme.panel, 0.55)
                ctx.beginPath(); arcAt(rOut * 0.95, 0, 359.99); ctx.stroke()

                // круги отклонения
                ctx.lineWidth = 1; ctx.font = Theme.px(11) + "px sans-serif"; ctx.textAlign = "left"; ctx.textBaseline = "middle"
                for (var k = 1; k <= 5; ++k) {
                    ctx.strokeStyle = pg.col(Theme.sub, k === 5 ? 0.8 : 0.35)
                    ctx.beginPath(); ctx.arc(cx, cy, Ri * k / 5, 0, 2 * Math.PI); ctx.stroke()
                    var v = pg.range * k / 5
                    ctx.fillStyle = pg.col(Theme.sub, 0.95)
                    ctx.fillText(Theme.dist(v, v < 10 ? 1 : 0), cx + 4, cy - Ri * k / 5 - 8)
                }
                ctx.strokeStyle = pg.col(Theme.sub, 0.25)
                ctx.beginPath(); ctx.moveTo(cx, cy - Ri); ctx.lineTo(cx, cy + Ri); ctx.moveTo(cx - Ri, cy); ctx.lineTo(cx + Ri, cy); ctx.stroke()

                // след судна относительно текущего положения (в масштабе круга отклонений)
                if (pg.trailOn) {
                    var tp = backend.trailPts, cn = st.n || 0, ce = st.e || 0, scT = Ri / pg.range, nT = Math.floor(tp.length / 2)
                    if (nT > 1) {
                        ctx.lineWidth = 2
                        for (var ti = 0; ti + 1 < nT; ++ti) {
                            var ax = (tp[2 * ti] - ce) * scT, ay = (tp[2 * ti + 1] - cn) * scT, bx = (tp[2 * ti + 2] - ce) * scT, by = (tp[2 * ti + 3] - cn) * scT
                            if (Math.hypot(ax, ay) > Ri && Math.hypot(bx, by) > Ri) continue
                            ctx.strokeStyle = pg.col(Theme.hull, 0.15 + 0.7 * ti / nT)
                            ctx.beginPath(); ctx.moveTo(cx + ax, cy - ay); ctx.lineTo(cx + bx, cy - by); ctx.stroke()
                        }
                    }
                }
                // уставка относительно судна
                var sc = Ri / pg.range
                var pvo = pg.pivotOffsetPx(sc), ox = cx + pvo[0], oy = cy + pvo[1]       // начало векторов — центр вращения
                var dN = (st.spN || 0) - (st.n || 0), dE = (st.spE || 0) - (st.e || 0)
                var dist = Math.hypot(dN, dE), clamped = dist * sc > Ri
                var kx = clamped ? Ri / dist : sc
                var sx = cx + dE * kx, sy = cy - dN * kx
                ctx.strokeStyle = pg.col(Theme.setpoint, 0.5); ctx.lineWidth = 1
                ctx.beginPath(); ctx.moveTo(ox, oy); ctx.lineTo(sx, sy); ctx.stroke()
                ctx.strokeStyle = pg.col(Theme.setpoint, 1); ctx.lineWidth = 2
                ctx.beginPath(); ctx.arc(sx, sy, 8, 0, 2 * Math.PI); ctx.moveTo(sx - 13, sy); ctx.lineTo(sx + 13, sy); ctx.moveTo(sx, sy - 13); ctx.lineTo(sx, sy + 13); ctx.stroke()
                if ((st.holdRadius || 0) > 0) {       // радиус удержания: граница (сплошная) и предупредительная зона 80 % (штрих) вокруг уставки
                    var rq = (st.errDist || 0) / st.holdRadius
                    var rcol = rq >= 1.0 ? Theme.bad : rq >= 0.8 ? Theme.warn : Theme.ok
                    ctx.strokeStyle = pg.col(rcol, 0.9); ctx.lineWidth = 2
                    ctx.beginPath(); ctx.arc(sx, sy, st.holdRadius * kx, 0, 2 * Math.PI); ctx.stroke()
                    ctx.strokeStyle = pg.col(rcol, 0.45); ctx.lineWidth = 1
                    if (ctx.setLineDash) ctx.setLineDash([4, 5])
                    ctx.beginPath(); ctx.arc(sx, sy, 0.8 * st.holdRadius * kx, 0, 2 * Math.PI); ctx.stroke()
                    if (ctx.setLineDash) ctx.setLineDash([])
                }
                if (pg.moving) {                      // новая точка, ещё не подтверждённая
                    var gE = pg.mvE - (st.e || 0), gN = pg.mvN - (st.n || 0)
                    var gx = cx + gE * sc, gy = cy - gN * sc
                    ctx.strokeStyle = pg.col(Theme.accent, 0.8); ctx.lineWidth = 1.5
                    if (ctx.setLineDash) ctx.setLineDash([5, 4])
                    ctx.beginPath(); ctx.moveTo(sx, sy); ctx.lineTo(gx, gy); ctx.stroke()
                    ctx.lineWidth = 2.5; ctx.beginPath(); ctx.arc(gx, gy, 10, 0, 2 * Math.PI); ctx.stroke()
                    if (ctx.setLineDash) ctx.setLineDash([])
                    ctx.beginPath(); ctx.moveTo(gx - 16, gy); ctx.lineTo(gx + 16, gy); ctx.moveTo(gx, gy - 16); ctx.lineTo(gx, gy + 16); ctx.stroke()
                }
                if (clamped) { ctx.fillStyle = pg.col(Theme.setpoint, 1); ctx.font = Theme.px(11) + "px sans-serif"; ctx.textAlign = "center"; ctx.fillText(Theme.dist(dist, 0), sx, sy + 24) }

                // корпус по контуру: L — условный размер значка, не реальная длина
                function hull(rotDeg, stroke, fill, dash, offN, offE, mark) {
                    // контур в истинном масштабе круга (уменьшается вместе с масштабом): по данным судна или свой (окно «Судно…»)
                    var own = backend.hullOwn === true
                    var Lm = own ? backend.hullLen : (st.length || 60), Bm = own ? backend.hullBeam : (st.beam || 14), bf = own ? backend.hullBow : 0.25
                    var L = Lm * sc, B = Bm * sc
                    var Lp = (st.length || 60) * sc, Bp = (st.beam || 14) * sc          // по ним считаются места датчиков и центр вращения
                    ctx.save(); ctx.translate(cx + (offE || 0) * sc, cy - (offN || 0) * sc); ctx.rotate(rotDeg * Math.PI / 180)
                    ctx.beginPath(); ctx.moveTo(0, -L / 2); ctx.lineTo(B / 2, -L / 2 + bf * L); ctx.lineTo(B / 2, L / 2); ctx.lineTo(-B / 2, L / 2); ctx.lineTo(-B / 2, -L / 2 + bf * L); ctx.closePath()
                    if (fill) { ctx.fillStyle = fill; ctx.fill() }
                    ctx.lineWidth = 2; ctx.strokeStyle = stroke
                    if (dash && ctx.setLineDash) ctx.setLineDash([6, 5])
                    ctx.stroke()
                    if (dash && ctx.setLineDash) ctx.setLineDash([])
                    if (mark) {                           // центр вращения: значок в масштабе силуэта (длина и ширина — по профилю судна)
                        var qx = pg.pivotY * sc, qy = -pg.pivotX * sc
                        ctx.strokeStyle = pg.col(Theme.accent, 1); ctx.fillStyle = pg.col(Theme.accent, 1); ctx.lineWidth = 2
                        ctx.beginPath(); ctx.arc(qx, qy, 6, 0, 2 * Math.PI); ctx.stroke()
                        ctx.beginPath(); ctx.arc(qx, qy, 2, 0, 2 * Math.PI); ctx.fill()
                        pg.drawAntennas(ctx, Bp, Lp)
                    }
                    ctx.restore()
                }
                // выбранный курс: пунктирный силуэт и линия
                if (pg.rotating) {
                    hull(pg.tgt, pg.col(Theme.accent, 1), null, true, pg.rotSp[0] - (st.spN || 0), pg.rotSp[1] - (st.spE || 0), false)
                    var q0 = P(rOut * 0.30, pg.tgt), q1 = P(rOut * 0.95, pg.tgt)
                    ctx.lineWidth = 2; ctx.strokeStyle = pg.col(Theme.accent, 0.9)
                    ctx.beginPath(); ctx.moveTo(q0[0], q0[1]); ctx.lineTo(q1[0], q1[1]); ctx.stroke()
                }
                hull(pg.psi, pg.col(Theme.hull, 1), pg.col(Theme.hull, 0.06), false, 0, 0, true)       // контур почти прозрачный
                // два вектора курса: заданный (зелёный, курс уставки) и текущий (жёлтый, курс судна)
                function vec(th, col, r1) {
                    var v0 = P(rOut * 0.20, th), v1 = P(r1, th), a = th * Math.PI / 180, ux = Math.sin(a), uy = -Math.cos(a)
                    ctx.lineWidth = 2.5; ctx.strokeStyle = col; ctx.fillStyle = col
                    ctx.beginPath(); ctx.moveTo(v0[0], v0[1]); ctx.lineTo(v1[0], v1[1]); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(v1[0], v1[1]); ctx.lineTo(v1[0] - 13 * ux - 5 * uy, v1[1] - 13 * uy + 5 * ux); ctx.lineTo(v1[0] - 13 * ux + 5 * uy, v1[1] - 13 * uy - 5 * ux); ctx.closePath(); ctx.fill()
                }
                if (pg.gHdg) vec(st.spPsi || 0, Theme.ok, rOut * 0.86)
                if (pg.yHdg) vec(pg.psi, Theme.warn, rOut * 0.80)
                function arrow2(x0, y0, x1, y1, col, w, dash) {
                    var d = Math.hypot(x1 - x0, y1 - y0); if (d < 3) return
                    var ux = (x1 - x0) / d, uy = (y1 - y0) / d, hs = Math.min(12, d * 0.5)
                    ctx.lineWidth = w; ctx.strokeStyle = col; ctx.fillStyle = col
                    if (dash && ctx.setLineDash) ctx.setLineDash([6, 4])
                    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke()
                    if (dash && ctx.setLineDash) ctx.setLineDash([])
                    ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x1 - hs * ux - hs * 0.45 * uy, y1 - hs * uy + hs * 0.45 * ux); ctx.lineTo(x1 - hs * ux + hs * 0.45 * uy, y1 - hs * uy - hs * 0.45 * ux); ctx.closePath(); ctx.fill()
                }
                // сила: запрос регулятора (зелёный) и упор движителей по распределению (жёлтый), в осях судна, длина — доля возможностей движителей
                if (pg.gForce || pg.yForce) {
                    var capM = Math.max(st.capX || 0, st.capY || 0, 0.001), kf = Ri * 0.7 / (0.25 * capM), a0 = pg.psi * Math.PI / 180
                    function fv(X, Y, col, off) {
                        var wN = X * Math.cos(a0) - Y * Math.sin(a0), wE = X * Math.sin(a0) + Y * Math.cos(a0)
                        var nx = Math.cos(a0), ny = Math.sin(a0)                                  // поперёк судна в экранных осях — для небольшого сдвига, чтобы векторы не слились
                        var ex = wE * kf, ey = wN * kf, ed = Math.hypot(ex, ey)
                        if (ed > Ri * 0.95) { ex *= Ri * 0.95 / ed; ey *= Ri * 0.95 / ed }
                        arrow2(ox + off * nx, oy + off * ny, ox + off * nx + ex, oy + off * ny - ey, col, 3, false)
                    }
                    if (pg.gForce) fv(st.tauX || 0, st.tauY || 0, Theme.ok, -3)
                    if (pg.yForce) fv(st.achX || 0, st.achY || 0, Theme.warn, 3)
                }
                // смещение: от судна к уставке (зелёный, штрих) и скорость над грунтом за vLook секунд (жёлтый)
                if (pg.gDisp) arrow2(ox, oy, sx, sy, Theme.ok, 2, true)
                if (pg.yDisp) {
                    // скорость самой точки (центра вращения): скорость судна плюс вращение вокруг центра
                    var po = pg.bodyToNE(pg.pivotX, pg.pivotY, pg.psi), rr = (st.rot || 0) * Math.PI / 180 / 60
                    var vx = (pg.smVe + rr * po[0]) * pg.vLook * sc, vy = (pg.smVn - rr * po[1]) * pg.vLook * sc, vd = Math.hypot(vx, vy)
                    if (vd > Ri) { vx *= Ri / vd; vy *= Ri / vd }
                    if (pg.velShown) arrow2(ox, oy, ox + vx, oy - vy, Theme.warn, 2, false)
                }

                // движители: стрелка — направление СТРУИ (судно толкает в противоположную сторону: вперёд — стрелки назад); зелёный — заданный командой, жёлтый — текущий; длина 100 % = 0,6 радиуса круга
                if (pg.gThr || pg.yThr) {
                    var ths = backend.thrusters || [], aT = pg.psi * Math.PI / 180, Lt = Ri * 0.6
                    for (var q = 0; q < ths.length; ++q) {
                        var th = ths[q]; var tx = th.x || 0, ty = th.y || 0
                        var pN = tx * Math.cos(aT) - ty * Math.sin(aT), pE = tx * Math.sin(aT) + ty * Math.cos(aT)
                        var qx0 = cx + pE * sc, qy0 = cy - pN * sc
                        function tv(pct, angRel, col, off) {
                            var ang = angRel * Math.PI / 180 + aT, k = (pct >= 0 ? -1 : 1), m = Math.min(1, Math.abs(pct) / 100) * Lt
                            if (m < 2) return
                            var ux = Math.sin(ang) * k, uy = -Math.cos(ang) * k
                            arrow2(qx0 - uy * off, qy0 + ux * off, qx0 - uy * off + ux * m, qy0 + ux * off + uy * m, col, 3, false)
                        }
                        var angCur = th.azimuth ? th.angle : (th.fixedAngle || 90), angCmd = th.azimuth ? th.cmdAngle : (th.fixedAngle || 90)
                        if (pg.gThr) tv(th.cmdPct || 0, angCmd, Theme.ok, -2)
                        if (pg.yThr) tv(th.pct || 0, angCur, Theme.warn, 2)
                        ctx.fillStyle = pg.col(Theme.text, 0.9); ctx.font = Theme.px(11) + "px sans-serif"; ctx.textAlign = "left"
                        ctx.fillText(th.id, qx0 + 6, qy0 - 6)
                    }
                }

                // дуга поворота (штриховка по кольцу) от текущего курса к выбранному
                if (pg.rotating) {
                    var steps = Math.abs(pg.delta), sgn = pg.delta >= 0 ? 1 : -1
                    ctx.lineWidth = 2; ctx.strokeStyle = pg.col(Theme.accent, 0.8)
                    for (var d = 0; d <= steps; d += 1) {
                        var th = pg.psi + sgn * d
                        var a = P(rOut * 0.91, th), b = P(rOut * 0.99, th)
                        ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke()
                    }
                }

                // ветер и волна на границе круга: стрелка с точки, ОТКУДА они приходят (истинный пеленг)
                function arrowIn(th, col, wavy) {
                    var tail = P(rOut * 1.0, th), head = P(rOut * 0.905, th)
                    var a = th * Math.PI / 180, ux = Math.sin(a), uy = -Math.cos(a)               // от судна наружу
                    var nx = -uy, ny = ux
                    ctx.lineJoin = "round"
                    ctx.strokeStyle = pg.col(Theme.bg, 0.9); ctx.lineWidth = 6
                    ctx.beginPath(); ctx.moveTo(tail[0], tail[1]); ctx.lineTo(head[0], head[1]); ctx.stroke()
                    ctx.strokeStyle = col; ctx.lineWidth = 3
                    ctx.beginPath()
                    if (wavy) {
                        var n = 14, len = Math.hypot(head[0] - tail[0], head[1] - tail[1])
                        for (var i = 0; i <= n; ++i) { var f = i / n, o = Math.sin(f * Math.PI * 4) * 3.5; var x = tail[0] + (head[0] - tail[0]) * f + nx * o, y = tail[1] + (head[1] - tail[1]) * f + ny * o; if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y) }
                    } else { ctx.moveTo(tail[0], tail[1]); ctx.lineTo(head[0], head[1]) }
                    ctx.stroke()
                    var w = 7, h2 = [head[0] + ux * 0, head[1] + uy * 0]
                    ctx.fillStyle = col; ctx.strokeStyle = pg.col(Theme.bg, 0.9); ctx.lineWidth = 1.5
                    ctx.beginPath(); ctx.moveTo(head[0] - ux * 7, head[1] - uy * 7); ctx.lineTo(head[0] + ux * 11 + nx * w, head[1] + uy * 11 + ny * w); ctx.lineTo(head[0] + ux * 11 - nx * w, head[1] + uy * 11 - ny * w); ctx.closePath(); ctx.fill(); ctx.stroke()
                }
                function tag(th, txt, col) {
                    var q = P(rOut * 0.80, th)
                    ctx.font = "bold " + Theme.px(12) + "px sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "middle"
                    ctx.lineWidth = 4; ctx.strokeStyle = pg.col(Theme.bg, 0.9); ctx.strokeText(txt, q[0], q[1])
                    ctx.fillStyle = col; ctx.fillText(txt, q[0], q[1])
                }
                var wdir = pg.norm((st.windToTrue || 0) + 180), vdir = pg.norm(st.waveFrom || 0)
                var showW = !!st.windValid, showV = !!st.waveDirValid
                if (showW && showV) {                     // если приходят с одной стороны — разводим значки, чтобы не лежали друг на друге
                    var dd = ((wdir - vdir + 540) % 360) - 180
                    if (Math.abs(dd) < 16) { var sh = (16 - Math.abs(dd)) / 2; wdir = pg.norm(wdir + (dd >= 0 ? sh : -sh)); vdir = pg.norm(vdir - (dd >= 0 ? sh : -sh)) }
                }
                if (showW) { arrowIn(wdir, "#a77bf3", false); tag(wdir, "ветер " + Theme.wind(st.windSpeed, 1), "#a77bf3") }
                if (showV) { arrowIn(vdir, "#2ec4b6", true); tag(vdir, "волна " + Theme.wave(st.waveHs, 1) + ", " + (st.waveTz || 0).toFixed(0) + " с", "#2ec4b6") }

                // деления компаса
                ctx.textAlign = "center"; ctx.textBaseline = "middle"
                for (var t = 0; t < 360; t += 5) {
                    var big = t % 30 === 0, mid = t % 10 === 0
                    var p0 = P(rOut * 0.965, t), p1 = P(rOut * (big ? 1.02 : mid ? 1.0 : 0.985), t)
                    ctx.lineWidth = big ? 2 : 1; ctx.strokeStyle = pg.col(Theme.sub, big ? 1 : 0.7)
                    ctx.beginPath(); ctx.moveTo(p0[0], p0[1]); ctx.lineTo(p1[0], p1[1]); ctx.stroke()
                    if (big) {
                        var lp = P(rOut + 15, t), lab = t === 0 ? "С" : t === 90 ? "В" : t === 180 ? "Ю" : t === 270 ? "З" : String(t)
                        ctx.fillStyle = pg.col(t % 90 === 0 ? Theme.text : Theme.sub, 1)
                        ctx.font = (t % 90 === 0 ? "bold " : "") + Theme.px(13) + "px sans-serif"
                        ctx.fillText(lab, lp[0], lp[1])
                    }
                }
                // метки курса на кольце: текущий (акцент), уставка (предупр.), выбранный (ручка)
                function tri(th, c) {
                    var a = P(rOut * 0.905, th), b = P(rOut * 0.99, th - 2.6), e = P(rOut * 0.99, th + 2.6)
                    ctx.fillStyle = c; ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.lineTo(e[0], e[1]); ctx.closePath(); ctx.fill()
                }
                tri(pg.psi, pg.col(Theme.accent, 1))
                if (pg.modeOn || st.spPending) { var m0 = P(rOut * 0.95, st.spPsi || 0); ctx.fillStyle = pg.col(Theme.warn, 1); ctx.beginPath(); ctx.arc(m0[0], m0[1], 5, 0, 2 * Math.PI); ctx.fill() }
                if (pg.rotating) {
                    var hp = P(rOut * 0.95, pg.tgt)
                    ctx.fillStyle = pg.col(Theme.accent, 1); ctx.strokeStyle = pg.col(Theme.text, 1); ctx.lineWidth = 2
                    ctx.beginPath(); ctx.arc(hp[0], hp[1], 11, 0, 2 * Math.PI); ctx.fill(); ctx.stroke()
                }
            }
        }
        // жест поворота: тянуть за кольцо компаса. Внутри круга жест не срабатывает, чтобы не повернуть судно случайно.
        MouseArea {
            anchors.fill: dial
            enabled: st.canControl && !pg.compact
            cursorShape: pg.moveDrag ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            function ang(mx, my) { return Math.atan2(mx - dial.cx, -(my - dial.cy)) * 180 / Math.PI }
            function hit(mx, my) { var r = Math.hypot(mx - dial.cx, my - dial.cy); return r >= dial.rOut * pg.kIn && r <= dial.rOut * 1.12 }
            onPressed: (m) => {
                var mk = pg.spPixel()
                if (Math.hypot(m.x - mk[0], m.y - mk[1]) < Theme.px(22)) { pg.moveDrag = true; pg.setMoveFromPixel(m.x, m.y) }     // красный крест — точка удержания
                else if (hit(m.x, m.y)) { pg.dragging = true; pg.setTarget(ang(m.x, m.y)) }                                      // кольцо — курс
                else m.accepted = false
            }
            onPositionChanged: (m) => { if (pg.moveDrag) pg.setMoveFromPixel(m.x, m.y); else if (pg.dragging) pg.setTarget(ang(m.x, m.y)) }
            onReleased: { pg.dragging = false; pg.moveDrag = false }
            onCanceled: { pg.dragging = false; pg.moveDrag = false }
        }
    }

    // ------------------------------------------------------------ панель «Поворот судна» (полоса внизу области)
    readonly property bool panelOn: (rotating || moving) && !compact
    readonly property real panelH: moving ? Theme.px(172) : Theme.px(170)
    Rectangle {
        id: rotPanel
        visible: pg.rotating && !pg.compact
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.px(6) }
        height: pg.panelH - Theme.px(6)
        radius: 8; color: pg.col(Theme.panel, 0.97); border.color: Theme.accent; border.width: 1
        readonly property real u: (width - Theme.px(24) - 5 * 6) / 8
        Column {
            x: Theme.px(12); y: Theme.px(8); width: parent.width - Theme.px(24); spacing: Theme.px(6)
            Row {
                spacing: Theme.px(10); height: Theme.px(40)
                Text { anchors.verticalCenter: parent.verticalCenter; text: "ПОВОРОТ"; color: Theme.sub; font.pixelSize: Theme.px(12); font.bold: true; font.letterSpacing: 0.8 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: (pg.delta > 0 ? "+" : "") + Math.round(pg.delta) + "°"; color: Theme.accent; font.pixelSize: Theme.px(28); font.bold: true; font.family: Theme.mono }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "→ " + Theme.hdg(pg.tgt); color: Theme.text; font.pixelSize: Theme.px(28); font.bold: true; font.family: Theme.mono }
                Text { anchors.verticalCenter: parent.verticalCenter; width: Math.max(0, rotPanel.width - x - Theme.px(24)); elide: Text.ElideRight; color: Theme.sub; font.pixelSize: Theme.px(12); font.family: Theme.mono
                       text: "вдоль " + Theme.f(st.errAlong, 1) + "  поперёк " + Theme.f(st.errCross, 1) + "  до уст. " + Theme.dist(st.errDist, 1) }
            }
            Row {
                spacing: Theme.px(8); height: Theme.px(24)
                Text { anchors.verticalCenter: parent.verticalCenter; color: Theme.sub; font.pixelSize: Theme.px(12); text: "Вокруг: " + pg.pivotName() }
                Text { anchors.verticalCenter: parent.verticalCenter; visible: pg.pivotOff; color: Theme.warn; font.pixelSize: Theme.px(12); text: "· центр судна сместится на " + Theme.f(pg.rotShift, 1) + " м" }
                Text { anchors.verticalCenter: parent.verticalCenter; color: Theme.accent; font.pixelSize: Theme.px(12); font.underline: true; text: "изменить…"
                       MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: pivotDlg.open() } }
            }
            Text { visible: !st.canControl || !pg.modeOn; width: parent.width; elide: Text.ElideRight; font.pixelSize: Theme.px(12)
                   color: st.canControl ? Theme.warn : Theme.bad
                   text: !st.canControl ? "Нет управления с этого поста: команда не будет отправлена." : "Режим не включён: курс применится при включении режима." }
            Row {
                spacing: 6
                Btn { width: rotPanel.u; text: "−10°"; onClicked: pg.setTarget(pg.tgt - 10) }
                Btn { width: rotPanel.u; text: "−1°"; onClicked: pg.setTarget(pg.tgt - 1) }
                Btn { width: rotPanel.u; text: "+1°"; onClicked: pg.setTarget(pg.tgt + 1) }
                Btn { width: rotPanel.u; text: "+10°"; onClicked: pg.setTarget(pg.tgt + 10) }
                Rectangle {
                    width: rotPanel.u * 2 + 6; height: Theme.px(44); radius: 8
                    color: okMa.pressed ? pg.col(Theme.ok, 0.35) : "transparent"; border.color: Theme.ok; border.width: 2; opacity: st.canControl ? 1 : 0.35
                    Text { anchors.centerIn: parent; text: "✓  Принять"; color: Theme.text; font.pixelSize: Theme.px(15); font.bold: true }
                    MouseArea { id: okMa; anchors.fill: parent; enabled: st.canControl; onClicked: pg.accept() }
                }
                Rectangle {
                    width: rotPanel.u * 2 + 6; height: Theme.px(44); radius: 8
                    color: noMa.pressed ? pg.col(Theme.bad, 0.35) : "transparent"; border.color: Theme.bad; border.width: 2
                    Text { anchors.centerIn: parent; text: "✕  Отмена"; color: Theme.text; font.pixelSize: Theme.px(15); font.bold: true }
                    MouseArea { id: noMa; anchors.fill: parent; onClicked: pg.cancel() }
                }
            }
        }
    }

    // ------------------------------------------------------------ подтверждение новой точки удержания
    Rectangle {
        id: movePanel
        visible: pg.moving && !pg.compact
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: Theme.px(6) }
        height: pg.panelH - Theme.px(6)
        radius: 8; color: pg.col(Theme.panel, 0.97); border.color: Theme.setpoint; border.width: 1
        readonly property var geo: backend.geoOf(pg.mvN, pg.mvE)
        readonly property real dN: pg.mvN - (st.spN || 0)
        readonly property real dE: pg.mvE - (st.spE || 0)
        readonly property real shift: Math.hypot(dN, dE)
        readonly property real brg: pg.norm(Math.atan2(dE, dN) * 180 / Math.PI)
        readonly property real fromShip: Math.hypot(pg.mvN - (st.n || 0), pg.mvE - (st.e || 0))
        Column {
            x: Theme.px(12); y: Theme.px(8); width: parent.width - Theme.px(24); spacing: Theme.px(4)
            Text { text: "НОВАЯ ТОЧКА УДЕРЖАНИЯ — ПОДТВЕРДИТЕ"; color: Theme.setpoint; font.pixelSize: Theme.px(12); font.bold: true; font.letterSpacing: 0.8 }
            Text { width: parent.width; elide: Text.ElideRight; color: Theme.text; font.pixelSize: Theme.px(18); font.bold: true; font.family: Theme.mono
                   text: "N " + Theme.f(pg.mvN, 1) + "   E " + Theme.f(pg.mvE, 1) + " м   курс " + Theme.hdg(st.spPsi || 0) }
            Text { visible: movePanel.geo.valid === true; width: parent.width; elide: Text.ElideRight; color: Theme.text; font.pixelSize: Theme.px(14); font.family: Theme.mono
                   text: movePanel.geo.valid === true ? Theme.coord(movePanel.geo.lat, true, 1) + "   " + Theme.coord(movePanel.geo.lon, false, 1) : "" }
            Text { width: parent.width; elide: Text.ElideRight; color: Theme.sub; font.pixelSize: Theme.px(13)
                   text: "Сдвиг уставки " + Theme.dist(movePanel.shift, 1) + " по пеленгу " + Theme.hdg(movePanel.brg) + "  ·  от судна " + Theme.dist(movePanel.fromShip, 1) }
            Text { visible: !st.canControl || !pg.modeOn; width: parent.width; elide: Text.ElideRight; font.pixelSize: Theme.px(12)
                   color: st.canControl ? Theme.warn : Theme.bad
                   text: !st.canControl ? "Нет управления с этого поста: команда не будет отправлена." : "Режим не включён: точка запомнится и применится при включении режима." }
            Row {
                spacing: 6
                Rectangle {
                    width: Theme.px(180); height: Theme.px(44); radius: 8
                    color: mvOk.pressed ? pg.col(Theme.ok, 0.35) : "transparent"; border.color: Theme.ok; border.width: 2; opacity: st.canControl ? 1 : 0.35
                    Text { anchors.centerIn: parent; text: "✓  Принять"; color: Theme.text; font.pixelSize: Theme.px(15); font.bold: true }
                    MouseArea { id: mvOk; anchors.fill: parent; enabled: st.canControl; onClicked: pg.acceptMove() }
                }
                Rectangle {
                    width: Theme.px(180); height: Theme.px(44); radius: 8
                    color: mvNo.pressed ? pg.col(Theme.bad, 0.35) : "transparent"; border.color: Theme.bad; border.width: 2
                    Text { anchors.centerIn: parent; text: "✕  Отмена"; color: Theme.text; font.pixelSize: Theme.px(15); font.bold: true }
                    MouseArea { id: mvNo; anchors.fill: parent; onClicked: pg.cancel() }
                }
            }
        }
    }

    PivotDialog {
        id: pivotDlg
        px: pg.pivotX; py: pg.pivotY
        shipLen: st.length || 60; shipBeam: st.beam || 14
        onApplied: (x, y) => backend.command("pivot " + x.toFixed(2) + " " + y.toFixed(2))
    }

    // условные обозначения векторов: зелёный — заданный, жёлтый — текущий
    Rectangle {      // подложка, чтобы подписи не сливались с сеткой и координатами
        visible: !pg.compact && legend.height > 0
        x: legend.x - 6; y: legend.y - 4; width: legend.width + 12; height: legend.height + 8; radius: 5
        color: Qt.rgba(Theme.panel.r, Theme.panel.g, Theme.panel.b, 0.82)
    }
    Column {
        id: legend
        visible: !pg.compact; anchors.right: parent.right; anchors.rightMargin: Theme.px(10); y: dialBox.height - height - Theme.px(20); spacing: 2
        Text { visible: pg.gHdg; anchors.right: parent.right; text: "курс заданный " + Theme.hdg(st.spPsi || 0) + " ▬"; color: Theme.ok; font.pixelSize: Theme.px(12); font.bold: true }
        Text { visible: pg.yHdg; anchors.right: parent.right; text: "курс текущий " + Theme.hdg(pg.psi) + " ▬"; color: Theme.warn; font.pixelSize: Theme.px(12); font.bold: true }
        Text { visible: pg.gForce; anchors.right: parent.right; text: "сила: запрос " + Theme.force(Math.hypot(st.tauX || 0, st.tauY || 0), 1) + " ➤"; color: Theme.ok; font.pixelSize: Theme.px(12); font.bold: true }
        Text { visible: pg.yForce; anchors.right: parent.right; text: "сила: упор " + Theme.force(Math.hypot(st.achX || 0, st.achY || 0), 1) + " ➤"; color: Theme.warn; font.pixelSize: Theme.px(12); font.bold: true }
        Text { visible: pg.gDisp; anchors.right: parent.right; text: "до уставки " + Theme.dist(st.errDist || 0, 1) + " ┅➤"; color: Theme.ok; font.pixelSize: Theme.px(12); font.bold: true }
        Text { visible: pg.yDisp; anchors.right: parent.right; text: pg.velShown ? "скорость ×" + pg.vLook + " с: " + Theme.speed(Math.hypot(pg.smVn, pg.smVe), 2) + " ➤" : "скорость < 0,03 м/с (не показана)"; color: pg.velShown ? Theme.warn : Theme.sub; font.pixelSize: Theme.px(12); font.bold: true }
        Text { visible: pg.gThr; anchors.right: parent.right; text: "движители: команда (струя) ➤"; color: Theme.ok; font.pixelSize: Theme.px(12); font.bold: true }
        Text { visible: pg.yThr; anchors.right: parent.right; text: "движители: упор (струя) ➤"; color: Theme.warn; font.pixelSize: Theme.px(12); font.bold: true }
    }

    Popup {
        id: vecPop
        x: Theme.px(8); y: pg.height - height - Theme.px(48); padding: Theme.px(10)
        background: Rectangle { color: Theme.panel; radius: 8; border.color: Theme.line }
        contentItem: Column { spacing: 6
            Text { text: "Векторы на круге"; color: Theme.text; font.pixelSize: Theme.px(14); font.bold: true }
            Grid { columns: 3; spacing: 6; rowSpacing: 6; verticalItemAlignment: Grid.AlignVCenter
                Item { width: Theme.px(150); height: 1 }
                Text { width: Theme.px(130); horizontalAlignment: Text.AlignHCenter; text: "Заданные"; color: Theme.ok; font.pixelSize: Theme.px(14); font.bold: true }
                Text { width: Theme.px(130); horizontalAlignment: Text.AlignHCenter; text: "Текущие"; color: Theme.warn; font.pixelSize: Theme.px(14); font.bold: true }
                Text { text: "Курс"; color: Theme.text; font.pixelSize: Theme.px(14) }
                Btn { width: Theme.px(130); text: pg.gHdg ? "✓ вкл" : "выкл"; active: pg.gHdg; onClicked: { pg.gHdg = !pg.gHdg; pg.setFlag("vecGHdg", pg.gHdg) } }
                Btn { width: Theme.px(130); text: pg.yHdg ? "✓ вкл" : "выкл"; active: pg.yHdg; onClicked: { pg.yHdg = !pg.yHdg; pg.setFlag("vecYHdg", pg.yHdg) } }
                Text { text: "Сила"; color: Theme.text; font.pixelSize: Theme.px(14) }
                Btn { width: Theme.px(130); text: pg.gForce ? "✓ запрос" : "выкл"; active: pg.gForce; onClicked: { pg.gForce = !pg.gForce; pg.setFlag("vecGForce", pg.gForce) } }
                Btn { width: Theme.px(130); text: pg.yForce ? "✓ упор" : "выкл"; active: pg.yForce; onClicked: { pg.yForce = !pg.yForce; pg.setFlag("vecYForce", pg.yForce) } }
                Text { text: "Смещение"; color: Theme.text; font.pixelSize: Theme.px(14) }
                Btn { width: Theme.px(130); text: pg.gDisp ? "✓ к уставке" : "выкл"; active: pg.gDisp; onClicked: { pg.gDisp = !pg.gDisp; pg.setFlag("vecGDisp", pg.gDisp) } }
                Btn { width: Theme.px(130); text: pg.yDisp ? "✓ скорость" : "выкл"; active: pg.yDisp; onClicked: { pg.yDisp = !pg.yDisp; pg.setFlag("vecYDisp", pg.yDisp) } }
                Text { text: "Движители"; color: Theme.text; font.pixelSize: Theme.px(14) }
                Btn { width: Theme.px(130); text: pg.gThr ? "✓ команда" : "выкл"; active: pg.gThr; onClicked: { pg.gThr = !pg.gThr; pg.setFlag("vecGThr", pg.gThr) } }
                Btn { width: Theme.px(130); text: pg.yThr ? "✓ упор" : "выкл"; active: pg.yThr; onClicked: { pg.yThr = !pg.yThr; pg.setFlag("vecYThr", pg.yThr) } }
            }
            Text { text: "Сила: 25 % возможностей = 70 % радиуса; движители: 100 % = 0,6 радиуса"; color: Theme.sub; font.pixelSize: Theme.px(11) }
        }
    }

    // ------------------------------------------------------------ радиус удержания
    Popup {
        id: radPop
        x: Theme.px(8); y: pg.height - height - Theme.px(48); padding: Theme.px(14); width: Theme.px(480)
        background: Rectangle { color: Theme.panel; radius: 8; border.color: Theme.line }
        onAboutToShow: radField.text = (st.holdRadius || 0) > 0 ? String(st.holdRadius) : ""
        function apply(v) { if (v >= 0.5 && v <= 50) { backend.command("radius " + v); radMsg.text = "" } else radMsg.text = "Допустимый радиус: от 0,5 до 50 м" }
        readonly property real r: st.holdRadius || 0
        readonly property string kind: r <= 0 ? "не задан — настройки закона по умолчанию" : r < 2 ? "ЖЁСТКОЕ удержание: быстрый контур, больше работа движителей" : r <= 6 ? "СРЕДНЕЕ удержание" : "МЯГКОЕ удержание: плавный контур, зона нечувствительности, меньше нагрузка"
        contentItem: Column { spacing: Theme.px(10)
            Text { text: "Радиус удержания"; color: Theme.text; font.pixelSize: Theme.px(16); font.bold: true }
            Text { width: parent.width; wrapMode: Text.WordWrap; color: Theme.sub; font.pixelSize: Theme.px(12)
                   text: "Допустимое удаление судна от точки позиционирования. От радиуса зависит настройка закона управления; при 80 % радиуса — предупреждение, при выходе за радиус — аларм." }
            Row { spacing: Theme.px(8)
                Repeater { model: [1, 2, 3, 5, 10, 20]
                    Btn { required property var modelData; width: Theme.px(58); text: modelData + " м"; active: Math.abs(radPop.r - modelData) < 0.01; enabledBtn: st.canControl
                          onClicked: radPop.apply(modelData) } } }
            Row { spacing: Theme.px(8)
                Text { text: "Свой радиус, м:"; color: Theme.text; font.pixelSize: Theme.px(14); anchors.verticalCenter: parent.verticalCenter }
                Rectangle { width: Theme.px(90); height: Theme.px(36); radius: 4; color: Theme.bg; border.color: Theme.line
                    TextInput { id: radField; anchors.fill: parent; anchors.margins: Theme.px(6); color: Theme.text; font.pixelSize: Theme.px(16); font.family: Theme.mono
                                inputMethodHints: Qt.ImhFormattedNumbersOnly; selectByMouse: true; enabled: st.canControl
                                onAccepted: radPop.apply(parseFloat(text.replace(",", "."))) } }
                Btn { text: "Применить"; enabledBtn: st.canControl; onClicked: radPop.apply(parseFloat(radField.text.replace(",", "."))) }
                Btn { text: "Выключить"; enabledBtn: st.canControl && radPop.r > 0; onClicked: { backend.command("radius off"); radField.text = "" } } }
            Text { id: radMsg; color: Theme.bad; font.pixelSize: Theme.px(12); visible: text !== "" }
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Text { text: "Сейчас: " + radPop.kind; width: parent.width; wrapMode: Text.WordWrap; color: Theme.text; font.pixelSize: Theme.px(13) }
            Item { width: parent.width; height: Theme.px(22); visible: radPop.r > 0
                Rectangle { anchors.fill: parent; radius: 3; color: Theme.bg; border.color: Theme.line }
                Rectangle { height: parent.height; radius: 3; width: Math.min(1, (st.errDist || 0) / Math.max(0.01, radPop.r)) * parent.width
                            color: (st.errDist || 0) >= radPop.r ? Theme.bad : (st.errDist || 0) >= 0.8 * radPop.r ? Theme.warn : Theme.ok }
                Rectangle { x: 0.8 * parent.width; width: 1; height: parent.height; color: Theme.sub }
                Text { anchors.centerIn: parent; text: Theme.dist(st.errDist || 0, 1) + " из " + Theme.dist(radPop.r, 1); color: Theme.text; font.pixelSize: Theme.px(12); font.family: Theme.mono } }
            Text { text: "⚠ Достижимость зависит от ветра, течения и мощности: если радиус слишком мал, будет предупреждение или аларм."; width: parent.width; wrapMode: Text.WordWrap; color: Theme.sub; font.pixelSize: Theme.px(11) }
        }
    }

    HullDialog { id: hullDlg }

    // ------------------------------------------------------------ масштаб
    Flow {          // кнопки переносятся на вторую строку, а не уходят за край
        visible: !pg.compact && !pg.panelOn
        id: rangeRow
        width: pg.width - Theme.px(16)
        x: Theme.px(8); y: pg.height - height - Theme.px(2)
        spacing: 6
        Btn { text: "－"; width: Theme.px(40); onClicked: pg.rangeIdx = Math.min(pg.ranges.length - 1, (pg.rangeIdx < 0 ? pg.ranges.indexOf(pg.autoRange) : pg.rangeIdx) + 1) }
        Btn { text: "＋"; width: Theme.px(40); onClicked: pg.rangeIdx = Math.max(0, (pg.rangeIdx < 0 ? pg.ranges.indexOf(pg.autoRange) : pg.rangeIdx) - 1) }
        Btn { text: "Авто"; active: pg.rangeIdx < 0; onClicked: pg.rangeIdx = -1 }
        Btn { text: "Карта…"; onClicked: pg.openMapSettings() }
        Btn { text: "Центр вращения…"; active: pg.pivotOff; onClicked: pivotDlg.open() }
        Btn { text: "Судно…"; active: backend.hullOwn === true; onClicked: hullDlg.open() }
        Btn { text: "Векторы…"; onClicked: vecPop.opened ? vecPop.close() : vecPop.open() }
        Btn { text: (st.holdRadius || 0) > 0 ? "Радиус " + (st.holdRadius % 1 === 0 ? st.holdRadius : Theme.f(st.holdRadius, 1)) + " м" : "Радиус удержания…"; active: radPop.opened; onClicked: radPop.opened ? radPop.close() : radPop.open() }
        Text { height: Theme.px(40); verticalAlignment: Text.AlignVCenter; text: "Круг = " + Theme.dist(pg.range, 0); color: Theme.sub; font.pixelSize: Theme.px(14) }
    }


    Text { visible: pg.compact; anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 2 }
           text: "Поворот: нужна область побольше"; color: Theme.sub; font.pixelSize: Theme.px(10) }
    Text { visible: !pg.compact && !pg.panelOn; anchors { right: parent.right; rightMargin: Theme.px(8); bottom: parent.bottom; bottomMargin: 4 }
           width: Math.max(0, pg.width - rangeRow.width - Theme.px(32)); horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft
           color: pg.sentText !== "" ? Theme.ok : Theme.sub; font.pixelSize: Theme.px(13); font.bold: pg.sentText !== ""
           text: pg.sentText !== "" ? pg.sentText : (st.canControl ? "Кольцо — курс; красный крест — точка" : "Пост в режиме наблюдения: управление недоступно") }

    // ------------------------------------------------------------ координаты и состояние привязки
    Rectangle {
        visible: !pg.compact
        x: Theme.px(8); y: Theme.px(30); width: geoCol.width + Theme.px(16); height: geoCol.height + Theme.px(10); radius: 6
        color: pg.col(Theme.panel, 0.82); border.color: Theme.line
        Column {
            id: geoCol; x: Theme.px(8); y: Theme.px(5); spacing: 1
            Text { font.family: Theme.mono; font.pixelSize: Theme.px(13); font.bold: true; color: st.geoValid && st.posValid ? Theme.text : Theme.sub
                   text: st.geoValid ? Theme.coord(st.lat, true, 1) + "   " + Theme.coord(st.lon, false, 1) : "Нет географической привязки" }
            Text { font.pixelSize: Theme.px(12); color: !st.geoValid ? Theme.warn : (!st.posValid ? Theme.bad : Theme.sub); font.bold: st.geoValid && !st.posValid
                   text: !st.geoValid ? "задайте начало координат (lat0, lon0)"
                       : (!st.posValid ? "НЕТ ПОЛОЖЕНИЯ: карта остаётся на последней точке"
                                       : (st.sim ? "положение: имитация" : "положение: " + st.posSource) + "  ±" + Theme.dist(st.posSigma, 2)) }
            Text { visible: st.geoValid && backend.mapName === ""; font.pixelSize: Theme.px(11); color: Theme.sub; text: "карта не загружена: показана градусная сетка" }
            Text { visible: st.geoValid && backend.mapName !== "" && pg.underlayOn && mu.mapMetresPerPixel * mu.plotRadius / pg.range > 3
                   font.pixelSize: Theme.px(11); color: Theme.warn
                   text: "карта грубая: " + Math.round(mu.mapMetresPerPixel) + " м на пиксель, на этом масштабе деталей не видно" }
        }
    }
}
