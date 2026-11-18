// Пульт оператора СДП. Шапка состояния, строка тревог и вкладки — всегда на экране
// (РС ч. XV 8.8.2, MSC.1/Circ.1580 3.4.1.3). Раскладка приспособлена к 1366×768 и выше.
// Вкладки: Главный, Опорные системы, Движители, Тренды, Возможности, Анализ отказов, Тревоги, Мощность, Настройки.
// На судне (настройка «бортовой режим») команды и метки имитатора скрыты.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Window
import QtCore
import "."

ApplicationWindow {
    id: win
    width: Math.min(1920, Screen.desktopAvailableWidth)
    height: Math.min(1080, Screen.desktopAvailableHeight)
    minimumWidth: 1280; minimumHeight: 700
    visible: true
    title: "СДП — пульт оператора" + (core.s.shipName ? " — " + core.s.shipName : "")
    color: Theme.bg
    font.family: Theme.font
    font.pixelSize: Theme.fs
    palette.window: Theme.bg; palette.windowText: Theme.text; palette.base: Theme.panel2; palette.text: Theme.text
    palette.button: Theme.panel2; palette.buttonText: Theme.text; palette.highlight: Theme.accent; palette.highlightedText: Theme.bg
    palette.mid: Theme.line; palette.dark: Theme.line; palette.light: Theme.panel2; palette.placeholderText: Theme.dim

    readonly property var s: core.s
    property real step: 1.0          // шаг сдвига точки, м
    property real hstep: 1.0         // шаг курса, °

    // настройки пульта (хранятся): палитра и бортовой режим; cliPalette/cliOnboard — временный override для снимков, в настройки не пишется
    Settings { id: prefs; property string palette: "night"; property bool onboard: false }
    Binding { target: Theme; property: "scheme"; value: cliPalette !== "" ? cliPalette : prefs.palette }
    readonly property bool onboard: cliOnboard || prefs.onboard

    FileDialog { id: shipDlg; title: "Книга данных судна"; nameFilters: ["Книги Excel (*.xlsx)"]; onAccepted: core.loadShip(selectedFile) }
    FileDialog { id: simDlg; title: "Книга имитатора"; nameFilters: ["Книги Excel (*.xlsx)"]; onAccepted: core.simStart(selectedFile) }

    component Panel: Rectangle { color: Theme.panel; radius: 3; clip: true }
    component Caption: Label { color: Theme.dim; font.pixelSize: Theme.fsSmall; font.capitalization: Font.AllUppercase; font.letterSpacing: 1 }
    component Big: Label { color: Theme.text; font.pixelSize: Theme.fsBig; font.family: Theme.mono }
    component Btn: Button { font.pixelSize: Theme.fs; implicitHeight: 40 }
    // Кнопка с подтверждением (РС ч. XV 8.5.7, MSC.1/Circ.1580 3.4.1.4: одно случайное нажатие не должно приводить к потере
    // положения; как двойное нажатие в K-Pos и Mega-Guard): первое нажатие — кнопка мигает «ещё раз», второе в течение 3 с — команда.
    property string armedCmd: ""
    Timer { id: armT; interval: 3000; onTriggered: win.armedCmd = "" }
    Timer { id: blinkT; interval: 400; repeat: true; running: win.armedCmd !== ""; property bool on: false; onTriggered: on = !on; onRunningChanged: on = true }
    component ConfirmBtn: Btn {
        property string cmd
        property string label
        readonly property bool armed: win.armedCmd === cmd
        text: armed ? "Ещё раз: " + label : label
        Rectangle { anchors.fill: parent; radius: 3; color: Theme.warn; opacity: parent.armed && blinkT.on ? 0.45 : 0; z: 1 }
        onClicked: {
            if (armed) { win.armedCmd = ""; armT.stop(); core.command(cmd) }
            else { win.armedCmd = cmd; armT.restart() }
        }
    }
    readonly property bool posLossOrReturn: { for (let i = 0; i < core.alarms.length; ++i) { const c = core.alarms[i].code; if (c === "POS_DROPOUT" || c === "POS_ALL_REJ" || c === "POS_RETURN") return true } return false }

    // Ряд строки тревог: плашка А/W, последнее сообщение с временем, «ещё N»; щелчок раскрывает список (как в K-Pos)
    component AlarmRow: Item {
        property string cls: "A"                    // "A" | "W"
        readonly property var rows: cls === "A" ? win.alarmsA : win.alarmsW
        readonly property bool expanded: win.expandAlm === cls
        Layout.fillWidth: true; implicitHeight: 16
        RowLayout {
            anchors.fill: parent; spacing: 6
            Rectangle { implicitWidth: 18; implicitHeight: 15; radius: 2; color: cls === "A" ? Theme.alarm : Theme.warn
                        Label { anchors.centerIn: parent; text: cls; color: Theme.bg; font.pixelSize: 10; font.bold: true } }
            Label { text: rows.length ? ("<b>" + rows[0].code + "</b>  " + rows[0].text + (rows[0].gone ? " (условие ушло)" : "") + (rows.length > 1 ? "   ·   ещё " + (rows.length - 1) : "")) : "—"
                    color: rows.length && !rows[0].gone ? Theme.text : Theme.dim; font.pixelSize: Theme.fsSmall; textFormat: Text.StyledText; elide: Text.ElideRight; Layout.fillWidth: true }
            Label { visible: rows.length > 0; text: rows.length ? win.fmtT(rows[0].tFirst) : ""; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.fsSmall }
            Label { visible: rows.length > 0; text: expanded ? "▾" : "▸"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
        }
        MouseArea { anchors.fill: parent; enabled: rows.length > 0; cursorShape: Qt.PointingHandCursor
                    onClicked: win.expandAlm = expanded ? "" : cls }
    }

    // строка тревог: раздельно аварии (А) и предупреждения (W), как два ряда в K-Pos; ряд раскрывается списком
    readonly property var alarmsA: core.alarms.filter(a => a.level <= 1)   // аварийные и тревоги (красный ряд)
    readonly property var alarmsW: core.alarms.filter(a => a.level === 2)  // предупреждения (жёлтый ряд)
    readonly property int unacked: core.alarms.filter(a => !a.acked && a.level < 3).length
    property string expandAlm: cliAlarmsExpand      // "" | "A" | "W" — раскрытый список строки тревог
    function fmtT(t) { return "t+" + Theme.num(t, 0) + " с" }

    // история для трендов: раз в секунду, 60 минут
    property var hist: ({ err: [], load: [], wind: [], pow: [] })
    property int trendWin: 15        // окно трендов, минут (5/15/60)
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            const h = win.hist
            h.err.push(s.posValid ? s.errDist : NaN)
            h.load.push(s.hasShip ? (s.load || 0) * 100 : NaN)
            h.wind.push(s.windValid ? Theme.knots(s.windSpeed) : NaN)
            h.pow.push(s.hasShip ? s.powerKW || 0 : NaN)
            if (h.err.length > 3600) { h.err.shift(); h.load.shift(); h.wind.shift(); h.pow.shift() }
            win.repaintTrends()
        }
    }
    function repaintTrends() { for (const c of trendCol.children) if (c.cv) c.cv.requestPaint() }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 6; spacing: 6

        // ------------------------------------------------ шапка состояния
        Panel {
            Layout.fillWidth: true; Layout.preferredHeight: 50
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 12
                Rectangle {
                    implicitWidth: stl.implicitWidth + 24; implicitHeight: 36; radius: 3
                    color: Theme.stateColor(s.stateCode)
                    Label { id: stl; anchors.centerIn: parent; text: s.state || ""; color: Theme.bg; font.bold: true; font.pixelSize: 18 }
                }
                Label { text: s.mode || ""; color: Theme.text; font.pixelSize: 18 }
                Rectangle {
                    visible: s.sim === true && !win.onboard; implicitWidth: siml.implicitWidth + 16; implicitHeight: 28; radius: 3; color: "transparent"; border.color: Theme.warn
                    Label { id: siml; anchors.centerIn: parent; text: "ИМИТАЦИЯ ×" + Theme.num(s.simSpeed, 0); color: Theme.warn; font.pixelSize: Theme.fsSmall }
                }
                Label { text: s.shipName || "судно не загружено"; color: Theme.dim; font.pixelSize: Theme.fsSmall; Layout.fillWidth: true; elide: Text.ElideRight }
                Label { text: "t = " + Theme.num(s.clock, 0) + " с"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.fsSmall }
                Btn { text: "Открыть судно…"; implicitHeight: 34; onClicked: shipDlg.open(); enabled: s.stateCode !== 3 }
                Btn { text: s.sim ? "Остановить имитатор" : "Запустить имитатор…"; implicitHeight: 34; visible: !win.onboard
                      enabled: s.hasShip === true && s.stateCode !== 3
                      onClicked: s.sim ? core.command("sim stop") : simDlg.open() }
            }
        }

        // ------------------------------------------------ строка тревог (не убирается ни в одном наборе)
        Panel {
            Layout.fillWidth: true; Layout.preferredHeight: 46
            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1
                    AlarmRow { cls: "A" }
                    AlarmRow { cls: "W" }
                }
                // колокол со счётчиком неподтверждённых (как в K-Pos): щелчок — вкладка «Тревоги»
                Item {
                    implicitWidth: 46; implicitHeight: 32
                    Canvas {
                        id: bell; anchors.fill: parent
                        property int n: win.unacked
                        onNChanged: requestPaint()
                        Connections { target: Theme; function onSchemeChanged() { bell.requestPaint() } }
                        onPaint: {
                            const g = getContext("2d"); g.reset()
                            const cx = width / 2 - 4, top = 4, w2 = 8
                            g.fillStyle = win.unacked > 0 ? Theme.text : Theme.dim
                            g.beginPath()
                            g.moveTo(cx - w2, top + 13)
                            g.quadraticCurveTo(cx - w2, top + 1, cx, top)          // купол
                            g.quadraticCurveTo(cx + w2, top + 1, cx + w2, top + 13)
                            g.lineTo(cx + w2 + 2, top + 16); g.lineTo(cx - w2 - 2, top + 16); g.closePath(); g.fill()
                            g.beginPath(); g.arc(cx, top + 19, 2.5, 0, 2 * Math.PI); g.fill()   // язычок
                        }
                    }
                    Rectangle {
                        visible: win.unacked > 0; anchors.right: parent.right; anchors.top: parent.top
                        implicitWidth: cnt.implicitWidth + 6; implicitHeight: 14; radius: 7; color: Theme.alarm
                        Label { id: cnt; anchors.centerIn: parent; text: win.unacked; color: Theme.bg; font.bold: true; font.pixelSize: 10 }
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tabs.currentIndex = 6 }
                }
                Btn { text: "Квитировать"; implicitHeight: 30; enabled: unacked > 0; onClicked: core.ack() }
            }
        }

        // Раскрытый список ряда тревог: время появления, число повторов, «условие ушло», квитирование по одной
        Panel {
            id: almDrop
            visible: win.expandAlm !== ""
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? Math.min(190, 44 + rows.length * 26) : 0
            readonly property var rows: win.expandAlm === "A" ? win.alarmsA : win.alarmsW
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 8; spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Caption { text: win.expandAlm === "A" ? "Тревоги — аварийные" : "Тревоги — предупреждения"; Layout.fillWidth: true }
                    Btn { text: "Скрыть"; implicitHeight: 24; font.pixelSize: Theme.fsSmall; onClicked: win.expandAlm = "" }
                }
                ListView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 2
                    model: almDrop.rows
                    delegate: RowLayout {
                        width: ListView.view.width; spacing: 8
                        Label { text: win.fmtT(modelData.tFirst); color: Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.fsSmall; Layout.preferredWidth: 80 }
                        Label { text: modelData.code; color: win.expandAlm === "A" ? Theme.alarm : Theme.warn; font.bold: true; font.pixelSize: Theme.fsSmall; Layout.preferredWidth: 170; elide: Text.ElideRight }
                        Label { text: modelData.text + (modelData.count > 1 ? "  ×" + modelData.count : "") + (modelData.gone ? "  · условие ушло" : "")
                                color: modelData.gone ? Theme.dim : Theme.text; font.pixelSize: Theme.fsSmall; Layout.fillWidth: true; elide: Text.ElideRight }
                        Label { visible: modelData.acked; text: "квитировано"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                        Btn { visible: !modelData.acked; text: "Квит."; implicitHeight: 22; font.pixelSize: Theme.fsSmall; onClicked: core.ackCode(modelData.code) }
                    }
                }
            }
        }

        // ------------------------------------------------ вкладки
        TabBar {
            id: tabs
            objectName: "tabbar"     // для --tab: программное открытие вкладки при снимках
            Layout.fillWidth: true; spacing: 2
            Repeater {
                model: ["Главный", "Опорные системы", "Движители", "Тренды", "Возможности", "Анализ отказов", "Тревоги", "Мощность", "Настройки"]
                // onClicked — чтобы вкладку можно было переключить и программным сигналом clicked() (проверки --press)
                TabButton { text: modelData; font.pixelSize: Theme.fsSmall; implicitHeight: 30; onClicked: tabs.currentIndex = index }
            }
        }

        StackLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            // ================================================ Главный
            RowLayout {
                spacing: 6

                PositionView {
                    id: plan
                    Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 820; Layout.minimumWidth: 460
                    s: core.s; hull: core.hull; thrusters: core.thrusters; track: core.track
                }

                ColumnLayout {
                    Layout.fillHeight: true; Layout.fillWidth: false; Layout.preferredWidth: 470; Layout.maximumWidth: 470; spacing: 6
                    // Курс и скорость: курс трёхзначный, поворот с полосой ЛБ/ПрБ, скорость в узлах со стороной,
                    // отклонение от точки со стороной (где судно относительно точки).
                    Panel {
                        id: hdgPanel
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 262
                        readonly property color hc: !s.hdgValid ? Theme.alarm : s.hdgDR ? Theme.warn : Theme.text
                        readonly property real offAlong: -(s.errAlong || 0)     // судно от точки: + к носу
                        readonly property real offCross: -(s.errCross || 0)     // + к правому борту
                        function sgn(v, d) { return (v > 0.0001 ? "+" : "") + Theme.num(v, d) }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Caption { text: "Курс и скорость"; Layout.fillWidth: true }
                                Rectangle {
                                    radius: 2; implicitWidth: srcL.implicitWidth + 12; implicitHeight: srcL.implicitHeight + 4
                                    color: !s.hdgValid ? Theme.alarm : s.hdgDR ? Theme.warn : Qt.darker(Theme.ok, 1.6)
                                    Label { id: srcL; anchors.centerIn: parent; font.pixelSize: 12; font.bold: true
                                            color: s.hdgValid && !s.hdgDR ? Theme.text : Theme.bg
                                            text: !s.hdgValid ? "НЕТ ДАННЫХ" : s.hdgDR ? "ПО СЧИСЛЕНИЮ" : "по гирокомпасам" }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 16
                                ColumnLayout {
                                    spacing: 0
                                    Label { text: s.hdgValid ? Theme.hdg3(s.hdg) : "НЕТ"; color: hdgPanel.hc; font.pixelSize: 40; font.family: Theme.mono }
                                    Label { text: "факт"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                                }
                                GridLayout {
                                    Layout.fillWidth: true; columns: 2; rowSpacing: 2; columnSpacing: 8
                                    Label { text: "задан"; color: Theme.dim; font.pixelSize: Theme.fsSmall; Layout.fillWidth: true }
                                    Label { text: Theme.hdg3(s.refHdg); color: Theme.accent; font.pixelSize: 19; font.family: Theme.mono; Layout.alignment: Qt.AlignRight }
                                    Label { text: "ошибка"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                                    Label { text: s.hdgValid ? hdgPanel.sgn(s.errHdg, 1) + "°" : "—"; color: Theme.text; font.pixelSize: 19; font.family: Theme.mono; Layout.alignment: Qt.AlignRight }
                                    Label { text: "поворот"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                                    Label { text: hdgPanel.sgn(s.rot, 1) + " °/мин"; color: Math.abs(s.rot || 0) > 3 ? Theme.warn : Theme.text
                                            font.pixelSize: 16; font.family: Theme.mono; Layout.alignment: Qt.AlignRight }
                                }
                            }
                            // полоса поворота: −10…+10 °/мин, ноль посередине; + — вправо
                            Item {
                                Layout.fillWidth: true; Layout.preferredHeight: 22
                                Rectangle { id: rotBar; width: parent.width; height: 8; y: 2; radius: 2; color: Theme.bg; border.color: Theme.line }
                                Rectangle {
                                    readonly property real p: Math.max(-1, Math.min(1, (s.rot || 0) / 10))
                                    y: rotBar.y + 1; height: rotBar.height - 2; radius: 1
                                    width: Math.abs(p) * rotBar.width / 2
                                    x: p >= 0 ? rotBar.width / 2 : rotBar.width / 2 - width
                                    color: Math.abs(s.rot || 0) > 3 ? Theme.warn : Theme.accent
                                }
                                Rectangle { x: rotBar.width / 2 - 1; y: 0; width: 2; height: 12; color: Theme.dim }
                                Label { y: 11; text: "◀ ЛБ 10 °/мин"; color: Theme.dim; font.pixelSize: 10 }
                                Label { y: 11; anchors.right: parent.right; text: "10 °/мин ПрБ ▶"; color: Theme.dim; font.pixelSize: 10 }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                            GridLayout {
                                Layout.fillWidth: true; columns: 3; rowSpacing: 0; columnSpacing: 14
                                Label { text: "над грунтом"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                                Label { text: "вдоль"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                                Label { text: "поперёк"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                                Label { text: Theme.num(Theme.knots(Math.hypot(s.u || 0, s.v || 0)), 2) + " уз"; color: Theme.text; font.pixelSize: 19; font.family: Theme.mono }
                                Label { text: Theme.num(Math.abs(Theme.knots(s.u || 0)), 2) + " уз " + ((s.u || 0) >= 0 ? "вперёд" : "назад"); color: Theme.text; font.pixelSize: Theme.fsSmall; font.family: Theme.mono }
                                Label { text: Theme.num(Math.abs(Theme.knots(s.v || 0)), 2) + " уз " + ((s.v || 0) >= 0 ? "к ПрБ" : "к ЛБ"); color: Theme.text; font.pixelSize: Theme.fsSmall; font.family: Theme.mono }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 12
                                ColumnLayout {
                                    spacing: 0
                                    Label { text: "от точки"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                                    Label { text: s.posValid ? Theme.num(s.errDist, 1) + " м" : "НЕТ"; font.pixelSize: 20; font.family: Theme.mono
                                            color: !s.posValid ? Theme.alarm : s.posDR ? Theme.warn : Theme.text }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 0
                                    Label { text: "судно " + Theme.num(Math.abs(hdgPanel.offAlong), 1) + " м " + (hdgPanel.offAlong >= 0 ? "к носу" : "к корме") + " · " + Theme.num(Math.abs(hdgPanel.offCross), 1) + " м " + (hdgPanel.offCross >= 0 ? "к ПрБ" : "к ЛБ")
                                            color: Theme.text; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Label {
                                        text: s.posDR ? "СЧИСЛЕНИЕ " + Theme.mmss(s.refLostS) + " · вероятный уход до " + Theme.num(s.drDriftM, 1) + " м"
                                             : s.geoValid ? Theme.latlon(s.lat, true) + "  " + Theme.latlon(s.lon, false)
                                             : "источник: " + (s.posSource || "—")
                                        color: s.posDR ? Theme.warn : Theme.dim; font.pixelSize: Theme.fsSmall; font.family: s.geoValid && !s.posDR ? Theme.mono : Theme.font
                                        elide: Text.ElideRight; Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }
                    Panel {
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: win.posLossOrReturn ? 244 : 196
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 6
                            Caption { text: "Режим" }
                            RowLayout {
                                spacing: 6
                                ConfirmBtn { label: "Ожидание"; cmd: "standby"; highlighted: s.modeCode === 0; Layout.fillWidth: true }
                                ConfirmBtn { label: "Курс"; cmd: "heading"; highlighted: s.modeCode === 3; enabled: s.stateCode >= 2; Layout.fillWidth: true }
                                ConfirmBtn { label: "Позиция"; cmd: "position"; highlighted: s.modeCode === 4; enabled: s.stateCode >= 2; Layout.fillWidth: true }
                            }
                            RowLayout {
                                spacing: 6
                                Btn { text: "Взять все движители"; enabled: s.hasShip === true; onClicked: core.command("thr_take all"); Layout.fillWidth: true }
                                ConfirmBtn { label: "Снять все"; cmd: "thr_release all"; enabled: s.hasShip === true; Layout.fillWidth: true }
                            }
                            Btn { text: "Держать здесь (не возвращаться в точку)"; visible: s.modeCode === 4 && win.posLossOrReturn; Layout.fillWidth: true
                                  palette.button: Theme.warn; palette.buttonText: Theme.bg; font.bold: true; onClicked: core.command("here") }
                            Label { color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true
                                    text: win.armedCmd !== "" ? "Нажмите ту же кнопку ещё раз в течение 3 с, чтобы подтвердить." : s.stateCode === 0 ? "Загрузите судно." : s.stateCode === 1 ? "Ядро ждёт курс и положение от датчиков." : s.stateCode === 2 ? "Возьмите движители и включите режим." : "Режим включён: изменения точки и курса — ниже." }
                        }
                    }
                    Panel {
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 168
                        enabled: s.stateCode === 3
                        opacity: enabled ? 1 : 0.5
                        GridLayout {
                            anchors.fill: parent; anchors.margins: 10; columns: 5; rowSpacing: 5; columnSpacing: 5
                            Caption { text: "Сдвиг точки"; Layout.columnSpan: 3 } Caption { text: "Курс"; Layout.columnSpan: 2 }
                            Item { width: 1 } Btn { text: "С ↑"; implicitHeight: 32; onClicked: core.command("move " + step + " 0") } Item { width: 1 }
                            Btn { text: "−" + hstep + "°"; implicitHeight: 32; onClicked: core.command("move 0 0 " + (-hstep)) } Btn { text: "+" + hstep + "°"; implicitHeight: 32; onClicked: core.command("move 0 0 " + hstep) }
                            Btn { text: "← З"; implicitHeight: 32; onClicked: core.command("move 0 " + (-step)) } Btn { text: "Ю ↓"; implicitHeight: 32; onClicked: core.command("move " + (-step) + " 0") } Btn { text: "В →"; implicitHeight: 32; onClicked: core.command("move 0 " + step) }
                            ComboBox { model: ["1°", "5°", "10°"]; onActivated: hstep = [1, 5, 10][currentIndex]; Layout.columnSpan: 2; Layout.fillWidth: true }
                            ComboBox { model: ["1 м", "5 м", "10 м"]; onActivated: step = [1, 5, 10][currentIndex]; Layout.columnSpan: 3; Layout.fillWidth: true }
                            Btn { text: "Точка = здесь"; implicitHeight: 32; Layout.columnSpan: 2; Layout.fillWidth: true
                                  onClicked: core.command("set " + s.n.toFixed(2) + " " + s.e.toFixed(2) + " " + s.hdg.toFixed(1)) }
                        }
                    }
                }

                // ------------------------------------------------ среда и анализ (кратко)
                ColumnLayout {
                    Layout.fillHeight: true; Layout.fillWidth: true; Layout.minimumWidth: 330; spacing: 6
                    Panel {
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 200
                        GridLayout {
                            anchors.fill: parent; anchors.margins: 10; columns: 2; rowSpacing: 4; columnSpacing: 12
                            Caption { text: "Ветер (откуда, от носа)" } Label { text: s.windValid ? Theme.num(s.windSpeed, 1) + " м/с (" + Theme.num(Theme.knots(s.windSpeed), 1) + " уз), " + Theme.num(s.windFromRel, 0) + "°" : "НЕТ"; color: s.windValid ? Theme.wind : Theme.warn; font.family: Theme.mono; elide: Text.ElideRight; Layout.fillWidth: true }
                            Caption { text: "Внешнее возмущение" } Label { text: Theme.num(Math.sqrt(s.distN * s.distN + s.distE * s.distE) / 1000, 0) + " кН, куда " + Theme.num((Math.atan2(s.distE, s.distN) * 180 / Math.PI + 360) % 360, 0) + "°"; color: Theme.dist; font.family: Theme.mono; elide: Text.ElideRight; Layout.fillWidth: true }
                            Caption { text: "Загрузка движителей" } Label { text: Theme.num(s.load * 100, 0) + " %"; color: s.load > 0.9 ? Theme.warn : Theme.text; font.family: Theme.mono; elide: Text.ElideRight; Layout.fillWidth: true }
                            Caption { text: "Мощность" }
                            Label {    // всего и по группам отказа (ГРЩ) — оценка по упору
                                text: { let t = Theme.num(s.powerKW, 0) + " кВт"; const b = s.busKW || {}; for (const k in b) t += " · " + k + " " + Theme.num(b[k], 0); return t }
                                color: Theme.text; font.family: Theme.mono; elide: Text.ElideRight; Layout.fillWidth: true
                            }
                            Caption { text: "Качка (крен / дифферент)" } Label { text: Theme.num(s.roll, 1) + "° / " + Theme.num(s.pitch, 1) + "°"; color: Theme.text; font.family: Theme.mono }
                            Caption { text: "Волнение (по МИО)" } Label { text: s.waveHs >= 0 ? Theme.num(s.waveHs, 1) + " м" : "не оценено"; color: Theme.text; font.family: Theme.mono }
                        }
                    }
                    Panel {
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredHeight: 190
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 4
                            Caption { text: "Анализ последствий отказа" }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Btn { text: "Класс 2"; implicitHeight: 28; Layout.fillWidth: true; highlighted: s.caClass === 2; enabled: s.hasShip === true; onClicked: core.command("class 2") }
                                Btn { text: "Класс 3"; implicitHeight: 28; Layout.fillWidth: true; highlighted: s.caClass === 3; enabled: s.hasShip === true; onClicked: core.command("class 3") }
                                Btn { text: "Выкл"; implicitHeight: 28; Layout.fillWidth: true; highlighted: s.caClass === 0; enabled: s.hasShip === true; onClicked: core.command("class off") }
                            }
                            Label { Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: Theme.fsSmall
                                    color: s.caClass === 0 ? Theme.dim : s.caAlarm ? Theme.alarm : s.caRan ? Theme.ok : Theme.dim
                                    text: s.caClass === 0 ? "Выключен. Для DYNPOS-2/3 включите класс (РС ч. XV 8.9.5). Подробно — вкладка «Анализ отказов»."
                                        : !s.caRan ? "Класс " + s.caClass + ": расчёт через 60 с в режиме «Позиция» при неизменных точке и курсе."
                                        : (s.caAlarm ? "НЕ ХВАТИТ упора при наихудшем отказе" : "Запас есть при всех отказах") + " (" + Theme.num(s.caAge, 0) + " с назад)." }
                        }
                    }
                }
            }

            // ================================================ Опорные системы
            Panel {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 4
                    Caption { text: "Датчики и опорные системы" }
                    ListView {
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                        model: core.sensors
                        delegate: RowLayout {
                            width: ListView.view.width; spacing: 8
                            Rectangle { implicitWidth: 10; implicitHeight: 10; radius: 5; color: modelData.valid ? (modelData.state === "OK" || modelData.state === "" ? Theme.ok : Theme.warn) : Theme.alarm }
                            Label { text: modelData.id; color: Theme.text; Layout.preferredWidth: 80; font.pixelSize: Theme.fsSmall }
                            Label { text: modelData.kind; color: Theme.dim; Layout.preferredWidth: 90; font.pixelSize: Theme.fsSmall }
                            // показание датчика: курс и расхождение, ветер в узлах, крен, качество GNSS; состояние — если не «норма»
                            Label {
                                readonly property var d: modelData
                                readonly property string reading: {
                                    if (!d.valid) return "нет данных"
                                    if (d.state && d.state !== "OK") return d.state
                                    if (d.kind === "курс" && d.hdgDeg !== undefined) return Theme.hdg3(d.hdgDeg) + "  Δ " + (Math.abs(d.dHdg) < 0.05 ? "0,0" : (d.dHdg > 0 ? "+" : "") + Theme.num(d.dHdg, 1)) + "°"
                                    if (d.kind === "ветер" && d.windMs !== undefined) return Theme.bearing(d.windFromRel) + " от носа · " + Theme.num(Theme.knots(d.windMs), 1) + " уз"
                                    if (d.kind === "качка" && d.roll !== undefined) return "крен " + Theme.num(Math.abs(d.roll), 1) + "° " + (d.roll < 0 ? "ЛБ" : "ПрБ") + " · дифф. " + Theme.num(d.pitch, 1) + "°"
                                    if (d.kind === "положение") {
                                        let t = ""
                                        if (d.gnssQ !== undefined && d.gnssQ >= 0) t = (d.gnssQ === 2 ? "DGPS" : d.gnssQ === 4 ? "RTK" : d.gnssQ === 5 ? "RTK float" : "GPS") + (d.gnssSats >= 0 ? " · " + d.gnssSats + " сп." : "") + (d.gnssHdop >= 0 ? " · HDOP " + Theme.num(d.gnssHdop, 1) : "")
                                        if (d.sdRep > 0) t += (t ? " · " : "") + "σ " + Theme.num(d.sdRep, 2) + " м"
                                        return t || "норма"
                                    }
                                    return "норма"
                                }
                                text: reading
                                color: !d.valid ? Theme.alarm : (d.state && d.state !== "OK") ? Theme.warn : (d.kind === "курс" && Math.abs(d.dHdg || 0) > 1) ? Theme.warn : Theme.text
                                Layout.fillWidth: true; font.pixelSize: Theme.fsSmall; font.family: Theme.mono; elide: Text.ElideRight
                            }
                            Label { text: modelData.age > 1 ? Theme.num(modelData.age, 1) + " с" : ""; color: modelData.valid ? Theme.dim : Theme.alarm; font.pixelSize: Theme.fsSmall; font.family: Theme.mono }
                        }
                    }
                }
            }

            // ================================================ Движители
            Panel {
                RowLayout {
                    anchors.fill: parent; anchors.margins: 8; spacing: 8
                    Repeater {
                        model: core.thrusters
                        delegate: ThrusterTile { t: modelData; Layout.fillWidth: true; Layout.preferredHeight: 280; Layout.maximumHeight: 280; Layout.alignment: Qt.AlignTop; Layout.maximumWidth: 420 }
                    }
                    Label { visible: core.thrusters.length === 0; text: "Движители появятся после загрузки судна"; color: Theme.dim; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
                    Item { Layout.fillWidth: true; Layout.fillHeight: true; visible: core.thrusters.length > 0 && core.thrusters.length < 5 }
                }
            }

            // ================================================ Тренды
            Panel {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        Caption { text: "Тренды"; Layout.fillWidth: true }
                        Repeater {
                            model: [5, 15, 60]
                            Btn { text: modelData + " мин"; implicitHeight: 26; highlighted: win.trendWin === modelData
                                  onClicked: { win.trendWin = modelData; win.repaintTrends() } }
                        }
                    }
                    ColumnLayout {
                        id: trendCol
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 4
                        // четыре тренда: отклонение от точки, загрузка движителей, ветер, мощность
                        Repeater {
                            model: [
                                { title: "Отклонение от точки, м", key: "err", fixedMax: 0 },
                                { title: "Загрузка движителей, %", key: "load", fixedMax: 100 },
                                { title: "Ветер, уз", key: "wind", fixedMax: 0 },
                                { title: "Мощность, кВт", key: "pow", fixedMax: 0 }
                            ]
                            delegate: ColumnLayout {
                                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 0
                                property alias cv: cv
                                Label { text: modelData.title; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                                Canvas {
                                    id: cv
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    onPaint: {
                                        const g = getContext("2d"); g.reset()
                                        const W = width, H = height
                                        const a = win.hist[modelData.key], n = Math.min(a.length, win.trendWin * 60)
                                        g.fillStyle = Theme.dim; g.font = Theme.cfont(10, false, true)
                                        if (n < 2) { g.textAlign = "center"; g.fillText("история набирается…", W / 2, height / 2); return }
                                        let mx = modelData.fixedMax
                                        if (!mx) { mx = 1; for (let i = a.length - n; i < a.length; ++i) if (!isNaN(a[i]) && a[i] > mx) mx = a[i]; mx = Math.ceil(mx * 1.2) }
                                        // сетка: 4 горизонтали со значениями
                                        g.strokeStyle = Theme.grid; g.lineWidth = 1; g.textAlign = "left"
                                        for (let i = 0; i <= 4; ++i) {
                                            const y = 4 + (H - 16) * i / 4
                                            g.beginPath(); g.moveTo(34, y); g.lineTo(W - 2, y); g.stroke()
                                            g.fillText(Theme.num(mx * (4 - i) / 4, mx < 10 ? 1 : 0), 2, y + 3)
                                        }
                                        g.textAlign = "right"; g.fillText("−" + win.trendWin + " мин", 34 + 46, H - 3)
                                        g.fillText("сейчас", W - 4, H - 3)
                                        // линия
                                        g.strokeStyle = Theme.accent; g.lineWidth = 1.5; g.beginPath()
                                        let started = false
                                        for (let i = 0; i < n; ++i) {
                                            const v = a[a.length - n + i]
                                            if (isNaN(v)) { started = false; continue }
                                            const x = 34 + (W - 38) * i / (n - 1), y = 4 + (H - 16) * (1 - v / mx)
                                            if (started) g.lineTo(x, y); else g.moveTo(x, y)
                                            started = true
                                        }
                                        g.stroke()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ================================================ Возможности
            Panel {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 10
                    Caption { text: "Запас возможностей: требуемое ядром усилие против предела движителей" }
                    GridLayout {
                        Layout.fillWidth: true; columns: 4; columnSpacing: 12; rowSpacing: 10
                        Repeater {
                            model: [
                                { name: "Продольное усилие", tau: Math.abs(s.tauX || 0) / 1000, cap: (s.capX || 0) / 1000, unit: "кН" },
                                { name: "Поперечное усилие", tau: Math.abs(s.tauY || 0) / 1000, cap: (s.capY || 0) / 1000, unit: "кН" },
                                { name: "Момент на курс", tau: Math.abs(s.tauN || 0) / 1000, cap: (s.capN || 0) / 1000, unit: "кН·м" }
                            ]
                            delegate: RowLayout {
                                Layout.fillWidth: true; Layout.columnSpan: 4; spacing: 10
                                Label { text: modelData.name; color: Theme.text; Layout.preferredWidth: 190 }
                                Rectangle {
                                    Layout.fillWidth: true; implicitHeight: 18; radius: 2; color: Theme.bg; border.color: Theme.line
                                    Rectangle {
                                        readonly property real p: modelData.cap > 0 ? Math.min(1, modelData.tau / modelData.cap) : 0
                                        width: p * parent.width; height: parent.height; radius: 2
                                        color: p > 0.9 ? Theme.warn : Theme.accent
                                    }
                                }
                                Label { text: Theme.num(modelData.tau, 1) + " / " + Theme.num(modelData.cap, 1) + " " + modelData.unit; color: Theme.text; font.family: Theme.mono; Layout.preferredWidth: 190 }
                                Label { text: modelData.cap > 0 ? Theme.num(modelData.tau / modelData.cap * 100, 0) + " %" : "—"
                                        color: modelData.cap > 0 && modelData.tau / modelData.cap > 0.9 ? Theme.warn : Theme.dim; font.family: Theme.mono }
                            }
                        }
                    }
                    Label { text: "Полярная диаграмма возможностей по ветру — в планах (дорожная карта, этап 1): в ядре есть, на пульт ещё не выведена."
                            color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Item { Layout.fillHeight: true }
                }
            }

            // ================================================ Анализ отказов
            Panel {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 6
                    Caption { text: "Анализ последствий отказа" }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        Btn { text: "Класс 2"; implicitHeight: 28; Layout.fillWidth: true; highlighted: s.caClass === 2; enabled: s.hasShip === true; onClicked: core.command("class 2") }
                        Btn { text: "Класс 3"; implicitHeight: 28; Layout.fillWidth: true; highlighted: s.caClass === 3; enabled: s.hasShip === true; onClicked: core.command("class 3") }
                        Btn { text: "Выкл"; implicitHeight: 28; Layout.fillWidth: true; highlighted: s.caClass === 0; enabled: s.hasShip === true; onClicked: core.command("class off") }
                    }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: Theme.fsSmall
                            color: s.caClass === 0 ? Theme.dim : s.caAlarm ? Theme.alarm : s.caRan ? Theme.ok : Theme.dim
                            text: s.caClass === 0 ? "Выключен. Для DYNPOS-2/3 включите класс (РС ч. XV 8.9.5)."
                                : !s.caRan ? "Класс " + s.caClass + ": расчёт через 60 с в режиме «Позиция» при неизменных точке и курсе."
                                : (s.caAlarm ? "НЕ ХВАТИТ упора при наихудшем отказе" : "Запас есть при всех отказах") + " (" + Theme.num(s.caAge, 0) + " с назад). Сила / момент, которые наберутся:"
                                  + (s.caSingle ? " · группы не заданы — одиночные отказы" : "") }
                    Repeater {
                        model: s.caGroups
                        delegate: RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Rectangle { implicitWidth: 10; implicitHeight: 10; radius: 5; color: modelData.alarm ? Theme.alarm : modelData.holds ? Theme.ok : Theme.warn }
                            Label { text: "отказ " + modelData.name + " (" + modelData.ids + ")"; color: Theme.text; Layout.fillWidth: true; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight }
                            Label { text: Theme.num(modelData.force, 0) + " / " + Theme.num(modelData.moment, 0) + " %"; color: modelData.holds ? Theme.text : Theme.alarm; font.pixelSize: Theme.fsSmall; font.family: Theme.mono }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // ================================================ Тревоги
            RowLayout {
                spacing: 6
                Panel {
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 2
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 6
                        RowLayout {
                            Caption { text: "Тревоги (" + core.alarms.length + ")"; Layout.fillWidth: true }
                            Btn { text: "Квитировать"; implicitHeight: 30; enabled: win.unacked > 0; onClicked: core.ack() }
                        }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 3
                            model: core.alarms
                            delegate: Rectangle {
                                width: ListView.view.width; height: al.implicitHeight + 12; radius: 2
                                color: modelData.level <= 1 ? Qt.rgba(0.9, 0.33, 0.29, modelData.acked ? 0.18 : 0.38) : modelData.level === 2 ? Qt.rgba(0.89, 0.7, 0.24, modelData.acked ? 0.12 : 0.28) : Theme.panel2
                                border.color: Theme.levelColor(modelData.level); border.width: modelData.acked ? 1 : 2
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 6; spacing: 8
                                    Label { id: al; Layout.fillWidth: true; wrapMode: Text.Wrap; color: modelData.gone ? Theme.dim : Theme.text; font.pixelSize: Theme.fsSmall
                                            text: win.fmtT(modelData.tFirst) + "  <b>" + modelData.code + "</b>  " + modelData.text
                                                + (modelData.count > 1 ? "  ×" + modelData.count : "") + (modelData.gone ? "  · условие ушло" : "") + (modelData.acked ? "  · квитировано" : "")
                                            textFormat: Text.StyledText }
                                    Btn { visible: !modelData.acked && modelData.level < 3; text: "Квит."; implicitHeight: 24; font.pixelSize: Theme.fsSmall; onClicked: core.ackCode(modelData.code) }
                                }
                            }
                            Label { visible: core.alarms.length === 0; text: "Тревог нет"; color: Theme.ok; anchors.centerIn: parent }
                        }
                    }
                }
                Panel {
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 3
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 8; spacing: 6
                        Caption { text: "Журнал" }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            model: core.log
                            delegate: Label { text: modelData; color: modelData.indexOf("ТРЕВОГА") >= 0 ? Theme.warn : Theme.dim; font.pixelSize: Theme.fsSmall; font.family: Theme.mono; width: ListView.view.width; elide: Text.ElideRight }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Caption { text: "Команда ядра (help — список)" }
                            TextField { id: cmd; Layout.fillWidth: true; placeholderText: "например: move 5 0"; font.family: Theme.mono
                                        onAccepted: { core.command(text); text = "" } }
                        }
                    }
                }
            }

            // ================================================ Мощность
            Panel {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        Caption { text: "Мощность (оценка по упору и кривой движителя, не измерение)"; Layout.fillWidth: true }
                        Big { text: Theme.num(s.powerKW, 0) + " кВт"; color: Theme.text }
                    }
                    Repeater {
                        model: Object.keys(s.busKW || {})
                        delegate: RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            Label { text: modelData; color: Theme.text; Layout.preferredWidth: 90 }
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 16; radius: 2; color: Theme.bg; border.color: Theme.line
                                Rectangle {
                                    width: (s.powerKW > 0 ? Math.min(1, (s.busKW || {})[modelData] / s.powerKW) : 0) * parent.width
                                    height: parent.height; radius: 2; color: Theme.accent
                                }
                            }
                            Label { text: Theme.num((s.busKW || {})[modelData], 0) + " кВт"; color: Theme.text; font.family: Theme.mono; Layout.preferredWidth: 90 }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                    GridLayout {
                        Layout.fillWidth: true; columns: 5; columnSpacing: 14; rowSpacing: 4
                        Caption { text: "Движитель" } Caption { text: "Группа" } Caption { text: "Упор" } Caption { text: "Обороты" } Caption { text: "Мощность" }
                        Repeater {
                            model: core.thrusters
                            delegate: RowLayout { Layout.columnSpan: 5; Layout.fillWidth: true; spacing: 14
                                Label { text: modelData.id; color: Theme.text; font.family: Theme.mono; Layout.preferredWidth: 90 }
                                Label { text: modelData.group || "—"; color: Theme.dim; Layout.preferredWidth: 80 }
                                Label { text: Theme.num(modelData.thrustKN, 1) + " кН"; color: Theme.text; font.family: Theme.mono; Layout.preferredWidth: 90 }
                                Label { text: Theme.num(modelData.rpmPct, 0) + " %"; color: Theme.text; font.family: Theme.mono; Layout.preferredWidth: 70 }
                                Label { text: Theme.num(modelData.powerKW, 0) + " / " + Theme.num(modelData.powerMaxKW, 0) + " кВт"; color: modelData.powerMaxKW > 0 && modelData.powerKW > 0.9 * modelData.powerMaxKW ? Theme.warn : Theme.text; font.family: Theme.mono }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // ================================================ Настройки
            Panel {
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 12
                    Caption { text: "Палитра" }
                    RowLayout {
                        spacing: 8
                        Repeater {
                            model: [ ["day", "День"], ["dusk", "Сумерки"], ["night", "Ночь"] ]
                            Btn { text: modelData[1]; implicitHeight: 32; highlighted: prefs.palette === modelData[0]
                                  onClicked: prefs.palette = modelData[0] }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                    Caption { text: "Бортовой режим" }
                    CheckBox { id: onboardCb; text: "Судно в эксплуатации: скрыть команды и метки имитатора"; checked: prefs.onboard
                               onToggled: prefs.onboard = checked; font.pixelSize: Theme.fs }
                    Label { color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true
                            text: "В бортовом режиме кнопки запуска и остановки имитатора и метка «ИМИТАЦИЯ» не показываются (дорожная карта, этап 1, п. 9)." }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                    Caption { text: "О программе" }
                    Label { text: "Пульт оператора СДП. Ядро в том же процессе. Изменение пределов и параметров судна — только через книгу судна с правами администратора."
                            color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
                    Item { Layout.fillHeight: true }
                }
            }
        }
    }
}
