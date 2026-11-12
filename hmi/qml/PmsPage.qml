import QtQuick
import QtQuick.Controls

// Окно PMS: схема электростанции — генераторы, две шины, секционный выключатель, потребители (пропульсивный комплекс и служебные).
// Данные имитации (не реальная PMS ⚠). Нажатие на генератор, шину или секционный выключатель в имитации меняет их состояние (команды «plant …»).
Item {
    id: pg
    readonly property var st: backend.s
    readonly property bool sim: st.sim
    function cmd(s) { backend.command("plant " + s) }
    function kw(v) { return Math.round(v).toLocaleString(Qt.locale("ru_RU"), "f", 0) }
    function gensOf(b) { var r = []; var g = st.plGens || []; for (var i = 0; i < g.length; ++i) if (g[i].bus === b) r.push(g[i]); return r }
    function thrOf(b) { var r = []; var t = backend.thrusters || []; for (var i = 0; i < t.length; ++i) if (t[i].bus === b) r.push(t[i]); return r }
    function thrKw(b) { var s = 0, t = thrOf(b); for (var i = 0; i < t.length; ++i) s += t[i].powerKW; return s }
    function svcKw(b) { return Math.max(0, (b === 0 ? st.plLoadA : st.plLoadB) - thrKw(b)) }
    function busFail(b) { return b === 0 ? st.plFailA : st.plFailB }
    function loadPct(b) { var a = (b === 0 ? st.plAvailA : st.plAvailB); var l = (b === 0 ? st.plLoadA : st.plLoadB); return a > 1 ? 100 * l / a : 0 }
    readonly property color busCol: Theme.accent

    Rectangle { anchors.fill: parent; radius: 8; color: Theme.panel; border.color: Theme.line }

    Text { x: Theme.px(16); y: Theme.px(10); text: "PMS — СИСТЕМА УПРАВЛЕНИЯ ЭЛЕКТРОПИТАНИЕМ"; color: Theme.text; font.pixelSize: Theme.px(20); font.bold: true }
    Chip { x: Theme.px(560); y: Theme.px(10); text: "ИМИТАЦИЯ, НЕ РЕАЛЬНАЯ PMS"; tone: Theme.warn; solid: true; visible: pg.sim }
    Text { visible: !st.plantOn; anchors.centerIn: parent; width: parent.width * 0.7; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; color: Theme.bad; font.pixelSize: Theme.px(18)
           text: "Электростанция не описана в настройках (раздел plant). Запустите ядро с config/salvage73_pms.json." }


    // ------------------------------------------------------------ карточки генераторов
    // ⚠ P и нагрузка — из имитации электростанции; U, f и I в ядре не моделируются: U и f показаны номинальными, ток рассчитан по P (cos φ = 0,8)
    readonly property real uNom: 660
    readonly property real fNom: 50
    function curA(g) { return g.online ? g.rated * g.load / 100 * 1000 / (Math.sqrt(3) * uNom * 0.8) : 0 }
    Row {
        id: gcards
        visible: st.plantOn
        x: Theme.px(16); y: Theme.px(46); spacing: Theme.px(10); width: sch.width; height: Theme.px(78)
        Repeater {
            model: st.plGens || []
            Rectangle {
                required property var modelData
                width: (gcards.width - gcards.spacing * Math.max(0, (st.plGens || []).length - 1)) / Math.max(1, (st.plGens || []).length); height: gcards.height
                radius: 8; color: Theme.panel2; border.width: 2; border.color: modelData.online ? Theme.ok : Theme.bad
                Text { x: Theme.px(10); y: Theme.px(6); text: modelData.id; color: Theme.text; font.pixelSize: Theme.px(16); font.bold: true }
                Chip { anchors { right: parent.right; top: parent.top; margins: Theme.px(6) } text: modelData.online ? "В РАБОТЕ" : "СТОП"; tone: modelData.online ? Theme.ok : Theme.bad; solid: true }
                Text { x: Theme.px(10); y: Theme.px(30); color: Theme.sub; font.pixelSize: Theme.px(12); font.family: Theme.mono
                       text: "P " + pg.kw(modelData.online ? modelData.rated * modelData.load / 100 : 0) + " кВт   U " + (modelData.online ? pg.uNom : 0) + " В\nf " + (modelData.online ? pg.fNom.toFixed(1) : "0.0") + " Гц   I " + Math.round(pg.curA(modelData)) + " А" }
                Rectangle { x: Theme.px(10); y: parent.height - Theme.px(12); width: parent.width - Theme.px(20); height: Theme.px(6); radius: 3; color: Theme.line
                    Rectangle { width: parent.width * Math.min(1, (modelData.online ? modelData.load : 0) / 100); height: parent.height; radius: 3
                                color: modelData.load > 90 ? Theme.bad : modelData.load > 75 ? Theme.warn : Theme.ok } }
            }
        }
    }

    // ------------------------------------------------------------ схема
    Item {
        id: sch
        visible: st.plantOn
        x: Theme.px(16); y: Theme.px(52) + Theme.px(86); width: parent.width - Theme.px(16) * 2 - side.width - Theme.px(12); height: parent.height - Theme.px(52) - Theme.px(86) - Theme.px(16) - Theme.px(210)
        readonly property real half: width / 2
        readonly property real genH: Theme.px(34)
        readonly property real busY: genH + Math.max(Theme.px(40), height * 0.08)
        readonly property real busH: Theme.px(34)
        readonly property real consY: busY + busH + Math.max(Theme.px(52), height * 0.09)
        readonly property real consH: Math.max(Theme.px(124), height * 0.22)

        // одна половина схемы: шина b (0 — A, 1 — B)
        component Half: Item {
            id: hf
            property int b: 0
            readonly property var gl: pg.gensOf(b === 0 ? "A" : "B")
            readonly property var tl: pg.thrOf(b)
            readonly property bool failed: pg.busFail(b)
            x: b === 0 ? 0 : sch.half + Theme.px(6); width: sch.half - Theme.px(6); height: sch.height
            readonly property color wire: failed ? Theme.bad : pg.busCol

            // генераторы
            Row {
                id: gr; spacing: Theme.px(10); width: parent.width; height: sch.genH
                Repeater {
                    model: hf.gl
                    Rectangle {
                        required property var modelData
                        width: (hf.width - Theme.px(10) * Math.max(0, hf.gl.length - 1)) / Math.max(1, hf.gl.length); height: sch.genH; radius: 8
                        color: Theme.panel2; border.width: 2; border.color: modelData.online ? Theme.ok : Theme.bad
                        Text { anchors.centerIn: parent; text: modelData.id + (modelData.online ? "" : " · СТОП"); color: modelData.online ? Theme.text : Theme.bad; font.pixelSize: Theme.px(15); font.bold: true }
                        Rectangle { x: parent.width / 2 - 1; y: parent.height; width: 3; height: sch.busY - sch.genH; color: modelData.online && !hf.failed ? pg.busCol : Theme.line }
                        MouseArea { anchors.fill: parent; enabled: pg.sim; onClicked: pg.cmd("gen " + (modelData.online ? "off " : "on ") + modelData.id) }
                    }
                }
            }
            // шина
            Rectangle {
                y: sch.busY; width: parent.width; height: sch.busH; radius: 4; color: hf.failed ? Theme.bad : pg.busCol; opacity: hf.failed ? 0.55 : 1
                Text { anchors.centerIn: parent; color: Theme.bg; font.pixelSize: Theme.px(15); font.bold: true
                       text: "Шина " + (hf.b === 0 ? "A" : "B") + " · 660 В / 50 Гц · " + pg.kw(hf.b === 0 ? st.plLoadA : st.plLoadB) + " из " + pg.kw(hf.b === 0 ? st.plAvailA : st.plAvailB) + " кВт" + (hf.failed ? " — ОТКАЗ" : "") }
                MouseArea { anchors.fill: parent; enabled: pg.sim; onClicked: pg.cmd("bus " + (hf.failed ? "on " : "off ") + (hf.b === 0 ? "A" : "B")) }
            }
            // потребители
            Row {
                y: sch.consY; spacing: Theme.px(10); width: parent.width
                Repeater {
                    model: hf.tl.length + 1
                    Rectangle {
                        required property int index
                        readonly property bool isSvc: index === hf.tl.length
                        readonly property var t: isSvc ? null : hf.tl[index]
                        width: (hf.width - Theme.px(10) * hf.tl.length) / (hf.tl.length + 1); height: sch.consH; radius: 8
                        color: Theme.panel2; border.width: 2; border.color: hf.failed ? Theme.bad : (isSvc ? Theme.line : Theme.accent)
                        Rectangle { x: parent.width / 2 - 1; y: -(sch.consY - sch.busY - sch.busH); width: 3; height: sch.consY - sch.busY - sch.busH; color: hf.wire }
                        Column { anchors.centerIn: parent; spacing: 2
                            Text { anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: Theme.px(16); font.bold: true; color: Theme.text
                                   text: isSvc ? "Служебные" : t.id }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: Theme.px(12); color: Theme.sub
                                   text: isSvc ? "потребители" : t.type }
                            Text { anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: Theme.px(16); font.bold: true; font.family: Theme.mono; color: Theme.text
                                   text: pg.kw(isSvc ? pg.svcKw(hf.b) : t.powerKW) + " кВт" }
                            Text { visible: !isSvc; anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: Theme.px(13); font.family: Theme.mono
                                   color: !isSvc && Math.abs(t.pct) > 90 ? Theme.warn : Theme.sub
                                   text: isSvc ? "" : "нагрузка " + Math.abs(t.pct).toFixed(0) + " %" + (t.azimuth ? " · " + ((t.angle + 180) % 360).toFixed(0) + "°" : "") }
                        }
                    }
                }
            }
        }
        Half { b: 0 }
        Half { b: 1 }

        // секционный выключатель между шинами
        Rectangle {
            x: sch.half - Theme.px(46); y: sch.busY - Theme.px(4); width: Theme.px(92); height: sch.busH + Theme.px(8); radius: 6; z: 3
            color: Theme.panel; border.width: 2; border.color: st.plTie ? Theme.ok : Theme.warn
            Column { anchors.centerIn: parent; spacing: 0
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: "СЕКЦ."; font.pixelSize: Theme.px(11); color: Theme.sub }
                Text { anchors.horizontalCenter: parent.horizontalCenter; text: st.plTie ? "ЗАМКНУТ" : "РАЗОМКНУТ"; font.pixelSize: Theme.px(13); font.bold: true; color: st.plTie ? Theme.ok : Theme.warn }
            }
            MouseArea { anchors.fill: parent; enabled: pg.sim; onClicked: pg.cmd("tie " + (st.plTie ? "open" : "close")) }
        }
        Rectangle { visible: st.plTie; x: sch.half - Theme.px(8); y: sch.busY + sch.busH / 2 - 2; width: Theme.px(16); height: 4; color: pg.busCol; z: 2 }
        Text { x: 0; y: sch.consY + sch.consH + Theme.px(12); width: sch.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; font.pixelSize: Theme.px(13); color: Theme.sub
               text: "В режиме ДП секционный выключатель разомкнут, шины работают раздельно; нагрузка на шины делится по подключённым движителям. Нажатие на генератор, шину или выключатель (в имитации) меняет их состояние." }
    }


    // ------------------------------------------------------------ сводка и тренд (внизу)
    property var hist: []            // строки: [суммарно, шина A, шина B] кВт, шаг 2 с, до 5 мин
    property int trendBus: 2         // 0 — шина A, 1 — шина B, 2 — обе
    readonly property real dpKw: thrKw(0) + thrKw(1)
    readonly property var trendCols: ["#f5b942", "#4da3ff", "#3ecf8e"]
    Timer { interval: 2000; repeat: true; running: pg.visible && st.plantOn
        onTriggered: { var row = [st.plLoad || 0, st.plLoadA || 0, st.plLoadB || 0]
                       var h = pg.hist.slice(-149); h.push(row); pg.hist = h; trend.requestPaint() } }
    Rectangle {
        id: trendBox
        visible: st.plantOn
        x: Theme.px(16); width: sch.width; height: Theme.px(198)
        anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.px(16)
        radius: 8; color: Theme.panel2; border.color: Theme.line
        Row { x: Theme.px(12); y: Theme.px(8); spacing: Theme.px(22)
            Repeater {
                model: [ { l: "MAX", v: st.plAvail, c: Theme.text }, { l: "ПОТРЕБЛЕНИЕ", v: st.plLoad, c: Theme.text },
                         { l: "ДП (движители)", v: pg.dpKw, c: Theme.accent }, { l: "ВНЕШНЕЕ (служебное)", v: Math.max(0, st.plLoad - pg.dpKw), c: Theme.sub },
                         { l: "ДОСТУПНО", v: st.plRes, c: st.plRes < 0 ? Theme.bad : st.plResPct < st.plMinPct ? Theme.warn : Theme.ok } ]
                Column { required property var modelData
                    Text { text: modelData.l; color: Theme.sub; font.pixelSize: Theme.px(11); font.bold: true }
                    Text { text: pg.kw(modelData.v) + " кВт"; color: modelData.c; font.pixelSize: Theme.px(18); font.bold: true; font.family: Theme.mono } }
            }
        }
        Canvas {
            id: trend
            x: Theme.px(12); y: Theme.px(58); width: parent.width - Theme.px(24) - Theme.px(150); height: parent.height - Theme.px(68)
            Connections { target: Theme; function onPresetChanged() { trend.requestPaint() } }
            onPaint: {
                var c = getContext("2d"); c.clearRect(0, 0, width, height)
                var h = pg.hist, mx = 100
                var ser = pg.trendBus === 2 ? [0, 1, 2] : [pg.trendBus + 1]
                for (var i = 0; i < h.length; ++i) for (var j = 0; j < ser.length; ++j) mx = Math.max(mx, h[i][ser[j]])
                var top = Math.ceil(mx * 1.1 / 500) * 500
                c.strokeStyle = Theme.line; c.fillStyle = Theme.sub; c.lineWidth = 1; c.font = Math.round(Theme.px(11)) + "px sans-serif"
                for (var k = 0; k <= 3; ++k) { var y = height - 14 - (height - 18) * k / 3; c.beginPath(); c.moveTo(40, y); c.lineTo(width, y); c.stroke(); c.fillText(Math.round(top * k / 3), 2, y + 4) }
                c.fillText("−5 мин", 40, height - 1); c.fillText("сейчас", width - 40, height - 1)
                for (var g = 0; g < ser.length; ++g) {
                    c.strokeStyle = pg.trendCols[ser[g]]; c.lineWidth = 2; c.beginPath()
                    for (var n = 0; n < h.length; ++n) { var x = width - (h.length - 1 - n) * (width - 40) / 149, yy = height - 14 - (height - 18) * h[n][ser[g]] / top; if (n === 0) c.moveTo(x, yy); else c.lineTo(x, yy) }
                    c.stroke()
                }
            }
        }
        Column { anchors { right: parent.right; rightMargin: Theme.px(12) } y: Theme.px(58); spacing: Theme.px(4)
            Text { text: "ТРЕНДЫ PMS"; color: Theme.sub; font.pixelSize: Theme.px(10); font.bold: true }
            Seg { width: Theme.px(136); px: Theme.px(11); model: ["Шина A", "Шина B", "Обе"]; current: pg.trendBus; onPicked: (i) => { pg.trendBus = i; trend.requestPaint() } }
            Repeater { model: [ { c: pg.trendCols[0], l: "Суммарная нагрузка" }, { c: pg.trendCols[1], l: "Шина A" }, { c: pg.trendCols[2], l: "Шина B" } ]
                Row { required property var modelData; spacing: 6
                    Rectangle { width: 14; height: 3; y: 6; color: modelData.c }
                    Text { text: modelData.l; color: Theme.text; font.pixelSize: Theme.px(12) } } }
        }
    }

    // ------------------------------------------------------------ сводка справа
    Rectangle {
        id: side
        visible: st.plantOn
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: Theme.px(16); topMargin: Theme.px(52) }
        width: Theme.px(300); radius: 8; color: Theme.panel2; border.color: Theme.line
        Column {
            x: Theme.px(12); y: Theme.px(10); width: parent.width - Theme.px(24); spacing: Theme.px(4)
            Text { text: "СУММАРНАЯ МОЩНОСТЬ"; color: Theme.sub; font.pixelSize: Theme.px(12); font.bold: true; font.letterSpacing: 0.8 }
            Readout { width: parent.width; px: Theme.px(15); label: "Доступно"; value: pg.kw(st.plAvail) + " кВт" }
            Readout { width: parent.width; px: Theme.px(15); label: "Потребление"; value: pg.kw(st.plLoad) + " кВт" }
            Readout { width: parent.width; px: Theme.px(15); label: "Резерв"; value: pg.kw(st.plRes) + " кВт (" + st.plResPct.toFixed(0) + " %)"
                      tone: st.plRes < 0 ? Theme.bad : st.plResPct < st.plMinPct ? Theme.warn : Theme.ok }
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Text { text: "НАПРЯЖЕНИЕ И ЧАСТОТА (номинал, не измеряется ⚠)"; color: Theme.sub; font.pixelSize: Theme.px(11); font.bold: true; width: parent.width; wrapMode: Text.Wrap }
            Readout { width: parent.width; px: Theme.px(14); label: "Шина A"; value: (pg.busFail(0) ? "0 В / 0 Гц" : pg.uNom + " В / " + pg.fNom + " Гц") }
            Readout { width: parent.width; px: Theme.px(14); label: "Шина B"; value: (pg.busFail(1) ? "0 В / 0 Гц" : pg.uNom + " В / " + pg.fNom + " Гц") }
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Text { text: "СОСТОЯНИЕ СЕТИ"; color: Theme.sub; font.pixelSize: Theme.px(12); font.bold: true; font.letterSpacing: 0.8 }
            Readout { width: parent.width; px: Theme.px(14); label: "Секционный выключатель"; value: st.plTie ? "замкнут" : "разомкнут"; tone: st.plTie ? Theme.ok : Theme.warn }
            Readout { width: parent.width; px: Theme.px(14); label: "Шины в работе"; value: (pg.busFail(0) || pg.busFail(1)) ? "ОТКАЗ шины" : "обе"; tone: (pg.busFail(0) || pg.busFail(1)) ? Theme.bad : Theme.ok }
            Readout { width: parent.width; px: Theme.px(14); label: "Резерв выше мин."; value: st.plResPct >= st.plMinPct ? "да" : "нет"; tone: st.plResPct >= st.plMinPct ? Theme.ok : Theme.warn }
            Readout { width: parent.width; px: Theme.px(14); label: "Худший отказ (DP-2)"; value: st.plWcOk ? "выполнено" : "не выполнено"; tone: st.plWcOk ? Theme.ok : Theme.bad }
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Text { text: "ПРОПУЛЬСИЯ"; color: Theme.sub; font.pixelSize: Theme.px(12); font.bold: true; font.letterSpacing: 0.8 }
            Repeater {
                model: backend.thrusters
                Readout { required property var modelData; width: parent.width; px: Theme.px(14); label: modelData.id + " (шина " + (modelData.bus === 0 ? "A" : modelData.bus === 1 ? "B" : "—") + ")"
                          value: pg.kw(modelData.powerKW) + " кВт · " + Math.abs(modelData.pct).toFixed(0) + " %" }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.line }
            Text { text: "ПРОВЕРКА НАИХУДШЕГО ОТКАЗА"; color: Theme.sub; font.pixelSize: Theme.px(12); font.bold: true; font.letterSpacing: 0.8 }
            Text { width: parent.width; wrapMode: Text.Wrap; font.pixelSize: Theme.px(14); color: st.plWcOk ? Theme.ok : Theme.warn
                   text: st.plWcOk ? "удержание сохраняется"
                         : (st.plWcRatio >= 10 ? "при потере " + st.plWc + " тяги не остаётся" : "при потере " + st.plWc + " нужно " + Math.round(100 * st.plWcRatio) + " % возможностей") }
            Rectangle { width: parent.width; height: 1; color: Theme.line; visible: pg.sim }
            Text { visible: pg.sim; text: "ИМИТАЦИЯ ОТКАЗОВ"; color: Theme.sub; font.pixelSize: Theme.px(12); font.bold: true; font.letterSpacing: 0.8 }
            Btn { visible: pg.sim; width: parent.width; text: st.plTie ? "Разомкнуть секционный" : "Замкнуть секционный"; onClicked: pg.cmd("tie " + (st.plTie ? "open" : "close")) }
            Btn { visible: pg.sim; width: parent.width; text: "Восстановить всё"; onClicked: pg.cmd("reset") }
        }
    }
}
