// Пульт оператора СДП. Шапка состояния, строка тревог и вкладки — всегда на экране
// (РС ч. XV 8.8.2, MSC.1/Circ.1580 3.4.1.3). Раскладка приспособлена к 1366×768 и выше.
// Вкладки: Главный, Опорные системы, Движители, Тренды, Возможности, Анализ отказов, Тревоги, Мощность, Настройки.
// На судне (настройка «бортовой режим») команды и метки имитатора скрыты.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Window
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

    // Настройки пульта (хранятся): палитра, бортовой режим и раскладки рабочих мест.
    // cli* — временные override для проверок и снимков, в настройки не пишутся.
    QtObject {
        id: prefs
        property string palette: core.settingValue("palette", "night"); property bool onboard: core.settingValue("onboard", false)
        property string workspaceLayout: core.settingValue("workspaceLayout", '["plan","hdg","mode","move","env","dev","power","ca"]')
        property string workspaceName: core.settingValue("workspaceName", "Полный")
        property string stationLayout: core.settingValue("stationLayout", ""); property string operatorLayout: core.settingValue("operatorLayout", "")
        property real devLimit: core.settingValue("devLimit", 5.0)
        onPaletteChanged: core.setSettingValue("palette", palette)
        onOnboardChanged: core.setSettingValue("onboard", onboard)
        onWorkspaceLayoutChanged: core.setSettingValue("workspaceLayout", workspaceLayout)
        onWorkspaceNameChanged: core.setSettingValue("workspaceName", workspaceName)
        onStationLayoutChanged: core.setSettingValue("stationLayout", stationLayout)
        onOperatorLayoutChanged: core.setSettingValue("operatorLayout", operatorLayout)
        onDevLimitChanged: core.setSettingValue("devLimit", devLimit)
    }
    Binding { target: Theme; property: "scheme"; value: cliPalette !== "" ? cliPalette : prefs.palette }
    readonly property bool onboard: cliOnboard || prefs.onboard

    FileDialog { id: shipDlg; title: "Книга данных судна"; nameFilters: ["Книги Excel (*.xlsx)"]; onAccepted: core.loadShip(selectedFile) }
    FileDialog { id: simDlg; title: "Книга имитатора"; nameFilters: ["Книги Excel (*.xlsx)"]; onAccepted: core.simStart(selectedFile) }
    FileDialog {
        id: recordDlg; title: "Выгрузить запись сеанса"; fileMode: FileDialog.SaveFile
        nameFilters: ["Журнал CSV (*.csv)"]; defaultSuffix: "csv"
        onAccepted: core.exportRecording(selectedFile)
    }
    FolderDialog {
        id: recordDirDlg; title: "Папка автоматической записи сеансов"
        onAccepted: core.setRecordingDirectory(selectedFolder)
    }

    // Своё рабочее место: 8 ячеек главного экрана. Порядок id — левый план, три средние и четыре правые ячейки.
    // Режим нельзя скрыть; шапка состояния и строка тревог находятся вне настраиваемой сетки и присутствуют всегда.
    readonly property var workspaceIds: ["plan", "hdg", "mode", "move", "env", "dev", "power", "ca"]
    readonly property var workspaceNames: ["План положения", "Курс и скорость", "Режим", "Сдвиг точки и курса", "Среда и загрузка", "Отклонение позиции", "Потребление мощности", "Анализ последствий"]
    readonly property var workspaceChoiceIds: workspaceIds.concat(["none"])
    readonly property var workspaceChoiceNames: workspaceNames.concat(["Пусто"])
    readonly property var defaultWorkspace: ["plan", "hdg", "mode", "move", "env", "dev", "power", "ca"]
    property int workspaceRev: 0
    property string workspaceNotice: ""
    readonly property real deviationLimit: Math.max(0.5, Math.min(50, prefs.devLimit))
    function presetWorkspace(name) {
        if (name === "watch") return ["plan", "hdg", "mode", "env", "dev", "power", "ca", "none"]
        if (name === "maneuver") return ["plan", "mode", "move", "hdg", "env", "dev", "none", "ca"]
        return defaultWorkspace.slice()
    }
    function normalizedWorkspace(a) {
        if (!a || a.length !== 8) return defaultWorkspace.slice()
        const seen = {}
        for (const id of a) {
            if (id === "none") continue
            if (workspaceIds.indexOf(id) < 0 || seen[id]) return defaultWorkspace.slice()
            seen[id] = true
        }
        return seen.mode ? a : defaultWorkspace.slice()
    }
    readonly property var activeWorkspace: {
        workspaceRev
        if (cliWorkspace !== "") return presetWorkspace(cliWorkspace)
        try { return normalizedWorkspace(JSON.parse(prefs.workspaceLayout)) }
        catch (e) { return defaultWorkspace.slice() }
    }
    readonly property string activeWorkspaceName: cliWorkspace === "watch" ? "Наблюдение" : cliWorkspace === "maneuver" ? "Манёвры" : cliWorkspace === "full" ? "Полный" : prefs.workspaceName
    function applyWorkspace() {
        if (!plan || !cell0) return
        const cells = [cell0, cell1, cell2, cell3, cell4, cell5, cell6, cell7]
        const panels = [plan, hdgPanel, modePanel, movePanel, envPanel, devPanel, powerPanel, caPanel]
        for (const p of panels) p.visible = false
        const layout = activeWorkspace
        for (let i = 0; i < cells.length; ++i) {
            cells[i].empty = layout[i] === "none"
            if (layout[i] === "none") continue
            const p = panels[workspaceIds.indexOf(layout[i])]
            p.parent = cells[i]; p.anchors.fill = cells[i]; p.visible = true
        }
    }
    function setWorkspace(layout, name) {
        const a = normalizedWorkspace(layout)
        prefs.workspaceLayout = JSON.stringify(a); prefs.workspaceName = name
        workspaceNotice = "Применён набор: " + name; workspaceRev++
    }
    function usePreset(name) {
        setWorkspace(presetWorkspace(name), name === "watch" ? "Наблюдение" : name === "maneuver" ? "Манёвры" : "Полный")
    }
    function setCellPanel(cellIndex, panelId) {
        const a = activeWorkspace.slice(), old = a[cellIndex]
        if (old === panelId) return
        if (old === "mode" && panelId === "none") {
            workspaceNotice = "Панель «Режим» обязательна и не скрывается"; workspaceRev++; return
        }
        if (panelId !== "none") {
            const other = a.indexOf(panelId)
            if (other >= 0) a[other] = old                  // повторов нет: панели меняются ячейками
        }
        a[cellIndex] = panelId
        setWorkspace(a, "Свой набор")
    }
    function saveWorkspace(kind) {
        if (kind === "station") prefs.stationLayout = prefs.workspaceLayout
        else prefs.operatorLayout = prefs.workspaceLayout
        workspaceNotice = kind === "station" ? "Текущая раскладка сохранена для поста" : "Текущая раскладка сохранена для оператора"
    }
    function applySavedWorkspace(kind) {
        const raw = kind === "station" ? prefs.stationLayout : prefs.operatorLayout
        if (!raw) return
        try { setWorkspace(JSON.parse(raw), kind === "station" ? "Пост" : "Оператор") }
        catch (e) { workspaceNotice = "Сохранённая раскладка повреждена — выберите готовый набор" }
    }
    Component.onCompleted: { applyWorkspace(); if (cliTrendDemo) fillTrendDemo() }
    onActiveWorkspaceChanged: Qt.callLater(applyWorkspace)

    component Panel: Rectangle { color: Theme.panel; radius: 3; clip: true }
    component WorkspaceCell: Item {
        property bool empty: false
        Rectangle {
            z: -1; anchors.fill: parent; visible: parent.empty; color: Theme.panel; radius: 3; border.color: Theme.line
            Label { anchors.centerIn: parent; text: "Пустая ячейка"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
        }
    }
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
    // Гирокомпасы 1-2-3: зелёный — норма, жёлтый — расхождение или отбраковка, красный — нет данных (как кружки в K-Pos)
    component GyroDots: Row {
        spacing: 4
        readonly property var gyros: core.sensors.filter(x => x.kind === "курс")
        Repeater {
            model: gyros
            delegate: Rectangle {
                width: 18; height: 18; radius: 9
                readonly property real dd: Math.abs(modelData.dHdg || 0)
                color: !modelData.valid ? Theme.alarm : ((modelData.state && modelData.state !== "OK") || dd > 1) ? Theme.warn : Theme.ok
                Label { anchors.centerIn: parent; text: modelData.id.replace("GYRO", ""); color: Theme.bg; font.pixelSize: 10; font.bold: true }
            }
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

    // история для трендов: раз в секунду, 60 минут; возмущение — модуль оценки неизвестной силы
    property var hist: ({ err: [], hdg: [], load: [], wind: [], dist: [], pow: [] })
    property int trendWin: 15        // окно трендов, минут (5/15/60)
    readonly property int trendPoints: { histTick; return Math.min(hist.err.length, trendWin * 60) }
    property int histTick: 0         // счётчик секунд — перерисовка мини-тренда мощности
    readonly property real powerMax: core.thrusters.reduce((a, t) => a + (t.powerMaxKW || 0), 0)   // установленная мощность, кВт
    Timer {
        interval: 1000; running: !cliTrendDemo; repeat: true
        onTriggered: {
            const h = win.hist
            h.err.push(s.posValid ? s.errDist : NaN)
            h.hdg.push(s.hdgValid ? s.hdg : NaN)
            h.load.push(s.hasShip ? (s.load || 0) * 100 : NaN)
            h.wind.push(s.windValid ? Theme.knots(s.windSpeed) : NaN)
            h.dist.push(s.posValid ? Math.hypot(s.distN || 0, s.distE || 0) / 1000 : NaN)
            h.pow.push(s.hasShip ? s.powerKW || 0 : NaN)
            if (h.err.length > 3600) {
                h.err.shift(); h.hdg.shift(); h.load.shift(); h.wind.shift(); h.dist.shift(); h.pow.shift()
            }
            win.histTick++
            win.repaintTrends()
        }
    }
    // Детерминированные 60 минут только для проверок и снимков; на судне cliTrendDemo не задаётся.
    function fillTrendDemo() {
        const h = win.hist
        for (let i = 0; i < 3600; ++i) {
            h.err.push(Math.max(0, 2.0 + 1.2 * Math.sin(i / 97) + 0.4 * Math.cos(i / 31)))
            h.hdg.push(((350 + i * 0.08 + 12 * Math.sin(i / 140)) % 360 + 360) % 360)
            h.load.push(Math.max(0, Math.min(100, 45 + 20 * Math.sin(i / 180) + 8 * Math.cos(i / 47))))
            h.wind.push(18 + 5 * Math.sin(i / 210) + 2 * Math.cos(i / 53))
            h.dist.push(Math.max(0, 30 + 12 * Math.sin(i / 160) + 4 * Math.cos(i / 43)))
            h.pow.push(500 + 120 * Math.sin(i / 180))
        }
        win.histTick++; win.repaintTrends()
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

            // ================================================ Главный: настраиваемые панели в 8 ячейках
            GridLayout {
                columns: 3; rows: 4; columnSpacing: 6; rowSpacing: 6

                WorkspaceCell {
                    id: cell0
                    Layout.row: 0; Layout.column: 0; Layout.rowSpan: 4
                    Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 820; Layout.minimumWidth: 460
                    PositionView {
                        id: plan; anchors.fill: parent
                        s: core.s; hull: core.hull; thrusters: core.thrusters; track: core.track
                    }
                }

                WorkspaceCell {
                    id: cell1
                    Layout.row: 0; Layout.column: 1
                    Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 470; Layout.minimumWidth: 470; Layout.maximumWidth: 470; Layout.preferredHeight: 262
                    // Курс и скорость: курс трёхзначный, поворот с полосой ЛБ/ПрБ, скорость в узлах со стороной,
                    // отклонение от точки со стороной (где судно относительно точки).
                    Panel {
                        id: hdgPanel; anchors.fill: parent
                        readonly property color hc: !s.hdgValid ? Theme.alarm : s.hdgDR ? Theme.warn : Theme.text
                        readonly property real offAlong: -(s.errAlong || 0)     // судно от точки: + к носу
                        readonly property real offCross: -(s.errCross || 0)     // + к правому борту
                        function sgn(v, d) { return (v > 0.0001 ? "+" : "") + Theme.num(v, d) }
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Caption { text: "Курс и скорость"; Layout.fillWidth: true }
                                GyroDots { }
                                Rectangle {
                                    radius: 2; implicitWidth: srcL.implicitWidth + 12; implicitHeight: srcL.implicitHeight + 4
                                    color: !s.hdgValid ? Theme.alarm : s.hdgDR ? Theme.warn : Qt.darker(Theme.ok, 1.6)
                                    Label { id: srcL; anchors.centerIn: parent; font.pixelSize: 12; font.bold: true
                                            color: s.hdgValid && !s.hdgDR ? "#ffffff" : Theme.bg
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
                }
                WorkspaceCell {
                    id: cell2
                    Layout.row: 1; Layout.column: 1
                    Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 470; Layout.minimumWidth: 470; Layout.maximumWidth: 470; Layout.preferredHeight: win.posLossOrReturn ? 244 : 196
                    Panel {
                        id: modePanel; anchors.fill: parent
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 6; spacing: 2
                            Caption { text: "Режим" }
                            RowLayout {
                                spacing: 6
                                ConfirmBtn { label: "Ожидание"; cmd: "standby"; highlighted: s.modeCode === 0; implicitHeight: 32; Layout.fillWidth: true }
                                ConfirmBtn { label: "Курс"; cmd: "heading"; highlighted: s.modeCode === 3; enabled: s.stateCode >= 2; implicitHeight: 32; Layout.fillWidth: true }
                                ConfirmBtn { label: "Позиция"; cmd: "position"; highlighted: s.modeCode === 4; enabled: s.stateCode >= 2; implicitHeight: 32; Layout.fillWidth: true }
                            }
                            RowLayout {
                                spacing: 6
                                Btn { text: "Взять все движители"; enabled: s.hasShip === true; onClicked: core.command("thr_take all"); implicitHeight: 32; Layout.fillWidth: true }
                                ConfirmBtn { label: "Снять все"; cmd: "thr_release all"; enabled: s.hasShip === true; implicitHeight: 32; Layout.fillWidth: true }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Caption { text: "Усиление"; Layout.fillWidth: true }
                                ConfirmBtn { label: "Низкое"; cmd: "gain low"; highlighted: s.gainHigh !== true; enabled: s.hasShip === true; implicitHeight: 32; Layout.fillWidth: true }
                                ConfirmBtn { label: "Высокое"; cmd: "gain high"; highlighted: s.gainHigh === true; enabled: s.hasShip === true; implicitHeight: 32; Layout.fillWidth: true }
                            }
                            Btn { text: "Держать здесь (не возвращаться в точку)"; visible: s.modeCode === 4 && win.posLossOrReturn; Layout.fillWidth: true
                                  palette.button: Theme.warn; palette.buttonText: Theme.bg; font.bold: true; onClicked: core.command("here") }
                            Label { color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true
                                    text: win.armedCmd !== "" ? "Нажмите ту же кнопку ещё раз в течение 3 с, чтобы подтвердить." : s.stateCode === 0 ? "Загрузите судно." : s.stateCode === 1 ? "Ядро ждёт курс и положение от датчиков." : s.stateCode === 2 ? "Возьмите движители и включите режим." : "Режим включён: изменения точки и курса — ниже." }
                        }
                    }
                }
                WorkspaceCell {
                    id: cell3
                    Layout.row: 2; Layout.column: 1; Layout.rowSpan: 2
                    Layout.fillHeight: true; Layout.fillWidth: true; Layout.preferredWidth: 470; Layout.minimumWidth: 470; Layout.maximumWidth: 470; Layout.preferredHeight: 168
                    Panel {
                        id: movePanel; anchors.fill: parent
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
                            Label {
                                Layout.columnSpan: 5; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.pixelSize: Theme.fsSmall
                                text: "Центр: " + (Math.abs(s.pivotX || 0) < 0.05 && Math.abs(s.pivotY || 0) < 0.05 ? "мидель" : Theme.num(Math.abs(s.pivotX || 0), 1) + " м " + ((s.pivotX || 0) >= 0 ? "к носу" : "к корме") + ", " + Theme.num(Math.abs(s.pivotY || 0), 1) + " м " + ((s.pivotY || 0) >= 0 ? "к ПрБ" : "к ЛБ"))
                                      + " · пределы: поворот " + ((s.rateRotDegMin || 0) > 0 ? Theme.num(s.rateRotDegMin, 1) + " °/мин" : "нет") + ", скорость " + ((s.rateSpeedKn || 0) > 0 ? Theme.num(s.rateSpeedKn, 2) + " уз" : "нет")
                            }
                        }
                    }
                }

                // ------------------------------------------------ среда и анализ (кратко)
                WorkspaceCell {
                    id: cell4
                    Layout.row: 0; Layout.column: 2
                    Layout.fillHeight: true; Layout.fillWidth: true; Layout.minimumWidth: 330; Layout.preferredHeight: 200
                    Panel {
                        id: envPanel; anchors.fill: parent
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
                }
                // Круговой индикатор отклонения: судно относительно заданной точки, нос вверх, кольцо настраивается
                WorkspaceCell {
                    id: cell5
                    Layout.row: 1; Layout.column: 2
                    Layout.fillHeight: true; Layout.fillWidth: true; Layout.minimumWidth: 330; Layout.preferredHeight: 138
                    Panel {
                        id: devPanel; anchors.fill: parent
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 12
                            Canvas {
                                id: devCv
                                Layout.preferredWidth: 112; Layout.preferredHeight: 112; Layout.alignment: Qt.AlignVCenter
                                property var st: win.s
                                onStChanged: requestPaint()
                                Connections { target: Theme; function onSchemeChanged() { devCv.requestPaint() } }
                                onPaint: {
                                    const g = getContext("2d"); g.reset()
                                    const cx = width / 2, cy = height / 2, R = Math.min(width, height) / 2 - 4
                                    g.strokeStyle = Theme.line; g.lineWidth = 1.5
                                    g.beginPath(); g.arc(cx, cy, R, 0, 2 * Math.PI); g.stroke()      // кольцо допуска
                                    g.strokeStyle = Theme.grid; g.lineWidth = 1; g.beginPath()
                                    g.moveTo(cx - R, cy); g.lineTo(cx + R, cy); g.moveTo(cx, cy - R); g.lineTo(cx, cy + R); g.stroke()
                                    g.strokeStyle = Theme.dim; g.beginPath()                          // заданная точка — крест в центре
                                    g.moveTo(cx - 5, cy); g.lineTo(cx + 5, cy); g.moveTo(cx, cy - 5); g.lineTo(cx, cy + 5); g.stroke()
                                    if (st.posValid !== true) {
                                        g.fillStyle = Theme.alarm; g.font = "bold 13px '" + Theme.font + "'"; g.textAlign = "center"
                                        g.fillText("НЕТ", cx, cy - R / 2); return
                                    }
                                    const a = -(st.errAlong || 0), c = -(st.errCross || 0)            // судно от точки: + нос / + ПрБ
                                    const d = Math.hypot(a, c), lim = win.deviationLimit
                                    if (d > 0.05) {                                                   // сектор направления отклонения ±12°
                                        const sa = Math.atan2(c, a) - Math.PI / 2                     // экранный угол (0 = нос вверх → -y)
                                        g.globalAlpha = 0.22; g.fillStyle = d > lim ? Theme.warn : Theme.accent
                                        g.beginPath(); g.moveTo(cx, cy)
                                        g.arc(cx, cy, R, sa - 0.21, sa + 0.21); g.closePath(); g.fill()
                                        g.globalAlpha = 1
                                    }
                                    const k = d > lim ? lim / d : 1                                   // за кольцом — точка на ободе
                                    g.fillStyle = d > lim ? Theme.warn : Theme.accent
                                    g.beginPath(); g.arc(cx + c * k / lim * R, cy - a * k / lim * R, 5, 0, 2 * Math.PI); g.fill()
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 2
                                Caption { text: "Отклонение позиции" }
                                Label { text: s.posValid ? Theme.num(s.errDist, 2) + " м" : "НЕТ"; font.pixelSize: 26; font.family: Theme.mono
                                        color: !s.posValid ? Theme.alarm : s.posDR || s.errDist > win.deviationLimit ? Theme.warn : Theme.text }
                                Label { text: "судно " + Theme.num(Math.abs(-(s.errAlong || 0)), 1) + " м " + (-(s.errAlong || 0) >= 0 ? "к носу" : "к корме") + " · " + Theme.num(Math.abs(-(s.errCross || 0)), 1) + " м " + (-(s.errCross || 0) >= 0 ? "к ПрБ" : "к ЛБ")
                                        color: Theme.text; font.pixelSize: Theme.fsSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                                Label { text: "кольцо = " + Theme.num(win.deviationLimit, 1) + " м, нос вверх"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                            }
                        }
                    }
                }
                // Потребление мощности: вертикальная шкала 0…установленная + мини-тренд 15 мин (как Power consumption в K-Pos)
                WorkspaceCell {
                    id: cell6
                    Layout.row: 2; Layout.column: 2
                    Layout.fillHeight: true; Layout.fillWidth: true; Layout.minimumWidth: 330; Layout.preferredHeight: 150
                    Panel {
                        id: powerPanel; anchors.fill: parent
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Caption { text: "Потребление мощности"; Layout.fillWidth: true }
                                Label { text: Theme.num(s.powerKW, 0) + " / " + Theme.num(win.powerMax, 0) + " кВт"; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.fsSmall }
                            }
                            RowLayout {
                                Layout.fillWidth: true; Layout.fillHeight: true; spacing: 10
                                Canvas {
                                    id: powBar
                                    Layout.preferredWidth: 52; Layout.fillHeight: true
                                    property var st: win.s
                                    onStChanged: requestPaint()
                                    Connections { target: Theme; function onSchemeChanged() { powBar.requestPaint() } }
                                    onPaint: {
                                        const g = getContext("2d"); g.reset()
                                        const W = width, H = height, max = Math.max(1, win.powerMax)
                                        const frac = Math.max(0, Math.min(1, (st.powerKW || 0) / max))
                                        g.fillStyle = Theme.bg; g.fillRect(4, 2, 14, H - 4)
                                        g.strokeStyle = Theme.line; g.strokeRect(4, 2, 14, H - 4)
                                        g.fillStyle = frac > 0.9 ? Theme.warn : Theme.ok
                                        g.fillRect(5, 2 + (H - 4) * (1 - frac), 12, (H - 4) * frac)
                                        g.fillStyle = Theme.dim; g.font = "10px '" + Theme.font + "'"; g.textAlign = "left"
                                        g.fillText(Theme.num(max, 0), 22, 11)
                                        g.fillText(Theme.num(max / 2, 0), 22, H / 2 + 3)
                                        g.fillText("0", 22, H - 3)
                                    }
                                }
                                Canvas {
                                    id: powMini
                                    Layout.fillWidth: true; Layout.fillHeight: true
                                    property int tk: win.histTick
                                    onTkChanged: requestPaint()
                                    Connections { target: Theme; function onSchemeChanged() { powMini.requestPaint() } }
                                    onPaint: {
                                        const g = getContext("2d"); g.reset()
                                        const W = width, H = height, max = Math.max(1, win.powerMax)
                                        const v = win.hist.pow.slice(-900)                  // 15 минут
                                        g.strokeStyle = Theme.grid; g.lineWidth = 1
                                        g.beginPath(); g.moveTo(0, H / 2); g.lineTo(W, H / 2); g.stroke()
                                        if (v.length < 2) {
                                            g.fillStyle = Theme.dim; g.font = "11px '" + Theme.font + "'"; g.textAlign = "center"
                                            g.fillText("история набирается…", W / 2, H / 2 - 6); return
                                        }
                                        g.strokeStyle = Theme.ok; g.lineWidth = 1.5; g.beginPath()
                                        let started = false
                                        for (let i = 0; i < v.length; ++i) {
                                            if (isNaN(v[i])) { started = false; continue }
                                            const x = i / 899 * W, y = H - 2 - Math.min(1, v[i] / max) * (H - 4)
                                            if (!started) { g.moveTo(x, y); started = true } else g.lineTo(x, y)
                                        }
                                        g.stroke()
                                    }
                                }
                            }
                        }
                    }
                }
                WorkspaceCell {
                    id: cell7
                    Layout.row: 3; Layout.column: 2
                    Layout.fillHeight: true; Layout.fillWidth: true; Layout.minimumWidth: 330; Layout.preferredHeight: 190
                    Panel {
                        id: caPanel; anchors.fill: parent
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
                        Btn { text: "5 мин"; implicitHeight: 26; highlighted: win.trendWin === 5
                              onClicked: { win.trendWin = 5; win.repaintTrends() } }
                        Btn { text: "15 мин"; implicitHeight: 26; highlighted: win.trendWin === 15
                              onClicked: { win.trendWin = 15; win.repaintTrends() } }
                        Btn { text: "60 мин"; implicitHeight: 26; highlighted: win.trendWin === 60
                              onClicked: { win.trendWin = 60; win.repaintTrends() } }
                    }
                    ColumnLayout {
                        id: trendCol
                        Layout.fillWidth: true; Layout.fillHeight: true; spacing: 4
                        // пять трендов дорожной карты; мощность остаётся мини-трендом на главном экране
                        Repeater {
                            model: [
                                { title: "Отклонение от точки, м", key: "err", fixedMax: 0 },
                                { title: "Курс, °", key: "hdg", fixedMax: 360 },
                                { title: "Загрузка движителей, %", key: "load", fixedMax: 100 },
                                { title: "Ветер, уз", key: "wind", fixedMax: 0 },
                                { title: "Возмущение (оценка), кН", key: "dist", fixedMax: 0 }
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
                                        const W = width, H = height, total = win.trendWin * 60
                                        const a = win.hist[modelData.key], n = Math.min(a.length, total)
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
                                        // линия: неполная история прижата вправо, ко всей ширине не растягивается
                                        g.strokeStyle = modelData.key === "dist" ? Theme.dist : modelData.key === "wind" ? Theme.wind : Theme.accent
                                        g.lineWidth = 1.5; g.beginPath()
                                        let started = false
                                        for (let i = 0; i < n; ++i) {
                                            const v = a[a.length - n + i]
                                            if (isNaN(v)) { started = false; continue }
                                            const x = 34 + (W - 38) * (total - n + i) / (total - 1), y = 4 + (H - 16) * (1 - v / mx)
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
            RowLayout {
                spacing: 6
                // Полярная диаграмма (capability plot): предельный и рабочий (80 % упора) ветер по направлениям от носа,
                // «Все движители» + отказ каждого; фиолетовая точка — текущий ветер. Как Capability plot в K-Pos.
                Panel {
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 3
                    Canvas {
                        id: capCv
                        anchors.fill: parent
                        property var curves: core.capCurves
                        property bool showFail: failChk.checked
                        property var st: win.s
                        onCurvesChanged: requestPaint()
                        onStChanged: requestPaint()
                        onShowFailChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        Connections { target: Theme; function onSchemeChanged() { capCv.requestPaint() } }
                        onPaint: {
                            const g = getContext("2d"); g.reset()
                            if (width < 100 || height < 100) return                     // промежуточный размер при создании окна
                            const cx = width / 2, cy = height / 2 + 6, R = Math.min(width, height) / 2 - 46
                            const maxV = 40.0                                            // шкала, м/с
                            g.strokeStyle = Theme.grid; g.lineWidth = 1
                            g.fillStyle = Theme.dim; g.font = "12px '" + Theme.font + "'"
                            for (let v = 10; v <= 40; v += 10) {                          // кольца 10/20/30/40 м/с
                                g.beginPath(); g.arc(cx, cy, R * v / maxV, 0, 2 * Math.PI); g.stroke()
                                g.textAlign = "left"; g.fillText(v + " м/с", cx + R * v / maxV * 0.707 + 4, cy - R * v / maxV * 0.707 - 2)
                            }
                            g.textAlign = "center"
                            for (let a = 0; a < 360; a += 30) {                           // спицы через 30°
                                const r = a * Math.PI / 180, sx = Math.sin(r), sy = Math.cos(r)
                                g.beginPath(); g.moveTo(cx, cy); g.lineTo(cx + sx * R, cy - sy * R); g.stroke()
                                g.fillText(a + "°", cx + sx * (R + 20), cy - sy * (R + 20) + 4)
                            }
                            g.fillStyle = Theme.text; g.font = "bold 14px '" + Theme.font + "'"
                            g.fillText("нос", cx, cy - R - 30)
                            if (!curves || curves.length === 0) {
                                g.fillStyle = Theme.dim; g.font = "14px '" + Theme.font + "'"
                                g.fillText("Нажмите «Рассчитать возможности»", cx, cy)
                                return
                            }
                            const pt = (dir, v) => [cx + Math.sin(dir * Math.PI / 180) * Math.min(v, maxV) / maxV * R,
                                                    cy - Math.cos(dir * Math.PI / 180) * Math.min(v, maxV) / maxV * R]
                            const path = (cv, key) => {
                                g.beginPath()
                                const n = cv.dirs.length
                                for (let i = 0; i <= n; ++i) {
                                    const p = pt(cv.dirs[i % n], cv[key][i % n])
                                    if (i === 0) g.moveTo(p[0], p[1]); else g.lineTo(p[0], p[1])
                                }
                                g.closePath()
                            }
                            if (showFail) for (let i = curves.length - 1; i >= 1; --i) {  // отказы — тонкие жёлтые
                                path(curves[i], "limit"); g.strokeStyle = Theme.warn; g.lineWidth = 1; g.stroke()
                            }
                            const all = curves[0]
                            path(all, "limit"); g.globalAlpha = 0.14; g.fillStyle = Theme.accent; g.fill(); g.globalAlpha = 1
                            g.strokeStyle = Theme.accent; g.lineWidth = 2; g.stroke()
                            path(all, "work"); g.strokeStyle = Theme.ok; g.lineWidth = 2; g.stroke()
                            if (st.windValid) {                                           // текущий ветер
                                const p = pt(st.windFromRel || 0, st.windSpeed || 0)
                                g.fillStyle = Theme.wind; g.beginPath(); g.arc(p[0], p[1], 6, 0, 2 * Math.PI); g.fill()
                                g.strokeStyle = Theme.bg; g.lineWidth = 1.5; g.stroke()
                                g.fillStyle = Theme.wind; g.font = "12px '" + Theme.font + "'"; g.textAlign = "left"
                                g.fillText("сейчас " + Theme.num(st.windSpeed, 1) + " м/с", p[0] + 9, p[1] - 6)
                            }
                            g.textAlign = "left"; g.font = "12px '" + Theme.font + "'"     // легенда
                            g.fillStyle = Theme.accent; g.fillText("— предел (полный упор)", 12, height - 34)
                            g.fillStyle = Theme.ok; g.fillText("— рабочий (80 % упора)", 12, height - 18)
                            if (showFail) { g.fillStyle = Theme.warn; g.fillText("— отказы движителей", 220, height - 18) }
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillHeight: true; Layout.preferredWidth: 470; Layout.maximumWidth: 470; spacing: 6
                    // Окно условий среды (как DP Capability Settings в K-Pos): течение, волны по ветру, граница поиска
                    Panel {
                        Layout.fillWidth: true; Layout.preferredHeight: 240
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 6
                            Caption { text: "Условия расчёта: ветер, волна и течение — с одного направления"; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            GridLayout {
                                columns: 2; columnSpacing: 10; rowSpacing: 4; Layout.fillWidth: true
                                Label { text: "Течение, м/с"; color: Theme.text; font.pixelSize: Theme.fsSmall }
                                TextField { id: curIn; text: "0,0"; Layout.preferredWidth: 90; font.family: Theme.mono; implicitHeight: 30 }
                                Label { text: "Волны"; color: Theme.text; font.pixelSize: Theme.fsSmall }
                                CheckBox { id: wavesChk; checked: true; text: "по ветру (Hs = 0,0246·V²)"; font.pixelSize: Theme.fsSmall }
                                Label { text: "Ветер max поиска, м/с"; color: Theme.text; font.pixelSize: Theme.fsSmall }
                                TextField { id: maxIn; text: "40"; Layout.preferredWidth: 90; font.family: Theme.mono; implicitHeight: 30 }
                            }
                            Btn { text: "Рассчитать возможности"; enabled: s.hasShip === true; implicitHeight: 34
                                  onClicked: core.capRun(Number(curIn.text.replace(",", ".")) || 0, wavesChk.checked, Number(maxIn.text.replace(",", ".")) || 40) }
                            Label { text: core.capInfo || "Расчёта ещё не было. По средним силам, курс постоянный — оценка по модели ядра, не по правилам РС."
                                    color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            Label { text: "Сейчас: " + (s.windValid ? "ветер " + Theme.num(s.windSpeed, 1) + " м/с с " + Theme.num(s.windFromRel, 0) + "° от носа" : "ветра нет") + (s.waveHs >= 0 ? ", Hs " + Theme.num(s.waveHs, 1) + " м" : "")
                                    color: Theme.text; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
                        }
                    }
                    Panel {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Caption { text: "Сценарии: наименьший предел / рабочий"; Layout.fillWidth: true }
                                CheckBox { id: failChk; checked: true; text: "отказы"; font.pixelSize: Theme.fsSmall }
                            }
                            ListView {
                                Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 3
                                model: core.capCurves
                                delegate: RowLayout {
                                    width: ListView.view.width; spacing: 8
                                    Rectangle { implicitWidth: 10; implicitHeight: 10; color: index === 0 ? Theme.accent : Theme.warn; radius: 2 }
                                    Label { text: modelData.name; color: Theme.text; font.pixelSize: Theme.fsSmall; Layout.fillWidth: true; elide: Text.ElideRight }
                                    Label { text: Theme.num(modelData.minLimit, 1) + " / " + Theme.num(modelData.minWork, 1) + " м/с"; color: Theme.text; font.family: Theme.mono; font.pixelSize: Theme.fsSmall }
                                }
                            }
                        }
                    }
                    Panel {
                        Layout.fillWidth: true; Layout.preferredHeight: 118
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 10; spacing: 6
                            Caption { text: "Запас по осям: требуемое усилие / предел" }
                            Repeater {
                                model: [
                                    { name: "Продольное", tau: Math.abs(s.tauX || 0) / 1000, cap: (s.capX || 0) / 1000, unit: "кН" },
                                    { name: "Поперечное", tau: Math.abs(s.tauY || 0) / 1000, cap: (s.capY || 0) / 1000, unit: "кН" },
                                    { name: "Момент", tau: Math.abs(s.tauN || 0) / 1000, cap: (s.capN || 0) / 1000, unit: "кН·м" }
                                ]
                                delegate: RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Label { text: modelData.name; color: Theme.text; font.pixelSize: Theme.fsSmall; Layout.preferredWidth: 86 }
                                    Rectangle {
                                        Layout.fillWidth: true; implicitHeight: 12; radius: 2; color: Theme.bg; border.color: Theme.line
                                        Rectangle {
                                            readonly property real p: modelData.cap > 0 ? Math.min(1, modelData.tau / modelData.cap) : 0
                                            width: p * parent.width; height: parent.height; radius: 2
                                            color: p > 0.9 ? Theme.warn : Theme.accent
                                        }
                                    }
                                    Label { text: modelData.cap > 0 ? Theme.num(modelData.tau / modelData.cap * 100, 0) + " %" : "—"
                                            color: modelData.cap > 0 && modelData.tau / modelData.cap > 0.9 ? Theme.warn : Theme.dim; font.family: Theme.mono; font.pixelSize: Theme.fsSmall }
                                }
                            }
                        }
                    }
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
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 10
                        Caption { text: "Прогноз загрузки комплекса"; Layout.fillWidth: true }
                        Label {
                            color: s.fcWarn ? Theme.alarm : Theme.dim; font.pixelSize: Theme.fsSmall
                            text: !s.fcOn ? "Выключен"
                                 : !s.fcValid ? "Накопление: " + Theme.num((s.fcDataSec || 0) / 60, 1) + " мин · прогноз появится после первых данных"
                                 : "Данные " + Theme.num((s.fcDataSec || 0) / 60, 1) + " мин · ячеек " + (s.fcFilled || 0) + "/" + (s.fcTotal || 0)
                                   + " · доверие " + Theme.num((s.fcConf || 0) * 100, 0) + " %" + (s.fcApply ? " · поправка применяется" : " · без поправки")
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 3
                            Caption { text: "Сейчас" }
                            Label { text: Theme.num((s.fcNow || 0) * 100, 0) + " %"; color: (s.fcNow || 0) >= (s.fcWarnRatio || 0.9) ? Theme.alarm : Theme.text; font.family: Theme.mono; font.pixelSize: 20 }
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 14; radius: 2; color: Theme.bg; border.color: Theme.line
                                Rectangle { width: Math.min(1, s.fcNow || 0) * parent.width; height: parent.height; radius: 2; color: (s.fcNow || 0) >= (s.fcWarnRatio || 0.9) ? Theme.alarm : Theme.accent }
                            }
                        }
                        Repeater {
                            model: s.fcHorizons || []
                            delegate: ColumnLayout {
                                Layout.fillWidth: true; spacing: 3
                                Caption { text: "+" + Theme.num(modelData.min, 0) + " мин" }
                                Label { text: Theme.num(modelData.load * 100, 0) + " %"; color: modelData.load >= (s.fcWarnRatio || 0.9) ? Theme.alarm : modelData.load >= (s.fcClearRatio || 0.8) ? Theme.warn : Theme.text; font.family: Theme.mono; font.pixelSize: 20 }
                                Rectangle {
                                    Layout.fillWidth: true; implicitHeight: 14; radius: 2; color: Theme.bg; border.color: Theme.line
                                    Rectangle { width: Math.min(1, modelData.load || 0) * parent.width; height: parent.height; radius: 2; color: modelData.load >= (s.fcWarnRatio || 0.9) ? Theme.alarm : modelData.load >= (s.fcClearRatio || 0.8) ? Theme.warn : Theme.ok }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        ConfirmBtn { label: s.fcOn ? "Выключить прогноз" : "Включить прогноз"; cmd: s.fcOn ? "forecast off" : "forecast on"; highlighted: s.fcOn === true; enabled: s.hasShip === true; implicitHeight: 32; Layout.fillWidth: true }
                        ConfirmBtn { label: s.fcApply ? "Не применять поправку" : "Применять поправку"; cmd: s.fcApply ? "forecast apply off" : "forecast apply on"; highlighted: s.fcApply === true; enabled: s.fcOn === true; implicitHeight: 32; Layout.fillWidth: true }
                        ConfirmBtn { label: "Очистить данные"; cmd: "forecast reset"; enabled: s.hasShip === true; implicitHeight: 32; Layout.fillWidth: true }
                    }
                    Label {
                        Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.dim; font.pixelSize: Theme.fsSmall
                        text: "Оценка по модели и накопленным данным, порывы не предсказываются. Накопление — в спокойном удержании после 120 с. Тревога FORECAST_LOAD: "
                              + Theme.num((s.fcWarnRatio || 0.9) * 100, 0) + " % на +" + Theme.num((s.fcWarnHorizonS || 300) / 60, 0) + " мин, снятие ниже " + Theme.num((s.fcClearRatio || 0.8) * 100, 0) + " %."
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // ================================================ Настройки
            Panel {
                RowLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 18
                    ScrollView {
                        id: wsScroll; Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 760; clip: true
                        contentWidth: availableWidth
                        ColumnLayout {
                            width: wsScroll.availableWidth; spacing: 8
                            Caption { text: "Своё рабочее место" }
                            Label { text: "Активный набор: " + activeWorkspaceName; color: Theme.text; font.pixelSize: Theme.fs }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Btn { text: "Полный"; implicitHeight: 32; Layout.fillWidth: true; highlighted: activeWorkspaceName === "Полный"; onClicked: usePreset("full") }
                                Btn { text: "Наблюдение"; implicitHeight: 32; Layout.fillWidth: true; highlighted: activeWorkspaceName === "Наблюдение"; onClicked: usePreset("watch") }
                                Btn { text: "Манёвры"; implicitHeight: 32; Layout.fillWidth: true; highlighted: activeWorkspaceName === "Манёвры"; onClicked: usePreset("maneuver") }
                            }
                            Label { color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true
                                    text: "Выберите панель для каждой ячейки. При выборе уже размещённой панели ячейки меняются местами. «Пусто» скрывает панель; режим скрыть нельзя." }
                            Repeater {
                                model: ["Левая большая ячейка", "Средняя ячейка 1", "Средняя ячейка 2", "Средняя ячейка 3", "Правая ячейка 1", "Правая ячейка 2", "Правая ячейка 3", "Правая ячейка 4"]
                                delegate: RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Label { text: modelData; color: Theme.dim; font.pixelSize: Theme.fsSmall; Layout.preferredWidth: 180 }
                                    ComboBox {
                                        Layout.fillWidth: true; implicitHeight: 30; font.pixelSize: Theme.fsSmall
                                        model: win.workspaceChoiceNames
                                        currentIndex: Math.max(0, win.workspaceChoiceIds.indexOf(win.activeWorkspace[index]))
                                        onActivated: win.setCellPanel(index, win.workspaceChoiceIds[currentIndex])
                                    }
                                }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                            Caption { text: "Сохранённые наборы" }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Label { text: "Пост"; color: Theme.text; Layout.preferredWidth: 80 }
                                Btn { text: "Сохранить текущий"; implicitHeight: 30; Layout.fillWidth: true; onClicked: saveWorkspace("station") }
                                Btn { text: "Применить пост"; implicitHeight: 30; Layout.fillWidth: true; enabled: prefs.stationLayout !== ""; onClicked: applySavedWorkspace("station") }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Label { text: "Оператор"; color: Theme.text; Layout.preferredWidth: 80 }
                                Btn { text: "Сохранить текущий"; implicitHeight: 30; Layout.fillWidth: true; onClicked: saveWorkspace("operator") }
                                Btn { text: "Применить оператора"; implicitHeight: 30; Layout.fillWidth: true; enabled: prefs.operatorLayout !== ""; onClicked: applySavedWorkspace("operator") }
                            }
                            Label { text: workspaceNotice; visible: workspaceNotice !== ""; color: Theme.accent; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                            Caption { text: "Кольцо отклонения позиции" }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Label { text: "Допуск, м (0,5…50)"; color: Theme.text; Layout.fillWidth: true }
                                TextField {
                                    implicitWidth: 90; implicitHeight: 30; text: Theme.num(deviationLimit, 1); font.family: Theme.mono
                                    onEditingFinished: { const v = Number(text.replace(",", ".")); if (isFinite(v)) prefs.devLimit = Math.max(0.5, Math.min(50, v)); text = Theme.num(deviationLimit, 1) }
                                }
                            }
                            Label { color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true
                                    text: "Порог меняет только отображение кольца и жёлтую индикацию отклонения. Шапка состояния, строка тревог и панель режима присутствуют в каждом наборе." }
                            Item { Layout.preferredHeight: 4 }
                        }
                    }
                    Rectangle { Layout.fillHeight: true; width: 1; color: Theme.line }
                    ScrollView {
                        id: generalScroll; Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 430; clip: true
                        contentWidth: availableWidth
                        ColumnLayout {
                            width: generalScroll.availableWidth; spacing: 12
                            Caption { text: "Палитра" }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Repeater {
                                    model: [ ["day", "День"], ["dusk", "Сумерки"], ["night", "Ночь"] ]
                                    Btn { text: modelData[1]; implicitHeight: 32; Layout.fillWidth: true; highlighted: prefs.palette === modelData[0]
                                          onClicked: prefs.palette = modelData[0] }
                                }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                            Caption { text: "Бортовой режим" }
                            CheckBox { id: onboardCb; text: "Судно в эксплуатации: скрыть команды и метки имитатора"; checked: prefs.onboard
                                       onToggled: prefs.onboard = checked; font.pixelSize: Theme.fs; Layout.fillWidth: true }
                            Label { color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true
                                    text: "В бортовом режиме кнопки запуска и остановки имитатора и метка «ИМИТАЦИЯ» не показываются (дорожная карта, этап 1, п. 9)." }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                            Caption { text: "Запись сеанса" }
                            Label {
                                Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: Theme.fsSmall
                                color: s.recActive === true ? Theme.ok : Theme.warn
                                text: (s.recActive === true ? "Запись ведётся автоматически" : "Запись недоступна")
                                      + "\n" + (s.recFile || "Журнал ещё не создан") + " · " + Theme.num((s.recBytes || 0) / 1024, 1) + " КБ"
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Btn { text: "Выбрать папку…"; implicitHeight: 32; Layout.fillWidth: true; onClicked: recordDirDlg.open() }
                                Btn { text: "Внутренняя папка"; implicitHeight: 32; Layout.fillWidth: true; onClicked: core.setRecordingDirectory("") }
                            }
                            Label {
                                Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; font.pixelSize: Theme.fsSmall
                                color: s.recFallback === true ? Theme.warn : Theme.dim
                                text: (s.recFallback === true ? "РЕЗЕРВ: внутренняя папка" : (s.recConfiguredDir || "") !== "" ? "Пользовательская папка (можно на флешке)" : "Внутренняя папка")
                                      + "\n" + (s.recDir || "Папка ещё не открыта")
                            }
                            Label {
                                text: s.recWarning || ""; visible: (s.recWarning || "") !== ""; color: Theme.warn; font.bold: true
                                font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true
                            }
                            Btn { text: "Выгрузить CSV"; implicitHeight: 32; Layout.fillWidth: true; enabled: (s.recBytes || 0) > 0; onClicked: recordDlg.open() }
                            Label { text: s.recNotice || ""; visible: (s.recNotice || "") !== ""; color: Theme.accent; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            Label { color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true
                                    text: "При смене папки начинается новый CSV. Если флешка извлечена или папка недоступна, запись продолжится на внутреннем диске. Возврат на флешку — повторным выбором папки. Выгрузка не останавливает запись; CSV подходит для tools/sdp_report.py." }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.line }
                            Caption { text: "Параметры управления" }
                            Label {
                                Layout.fillWidth: true; wrapMode: Text.Wrap; color: Theme.text; font.pixelSize: Theme.fsSmall
                                text: "Сейчас: " + (Math.abs(s.pivotX || 0) < 0.05 && Math.abs(s.pivotY || 0) < 0.05 ? "центр — мидель" : "центр " + Theme.num(Math.abs(s.pivotX || 0), 1) + " м " + ((s.pivotX || 0) >= 0 ? "к носу" : "к корме") + ", " + Theme.num(Math.abs(s.pivotY || 0), 1) + " м " + ((s.pivotY || 0) >= 0 ? "к ПрБ" : "к ЛБ"))
                                      + "\nУсиление: " + (s.gainHigh === true ? "высокое (×" + Theme.num(s.gainHighK || 0, 2) + ")" : "низкое")
                                      + "\nПределы: поворот " + ((s.rateRotDegMin || 0) > 0 ? Theme.num(s.rateRotDegMin, 1) + " °/мин" : "нет") + ", скорость " + ((s.rateSpeedKn || 0) > 0 ? Theme.num(s.rateSpeedKn, 2) + " уз" : "нет")
                            }
                            Label { text: "Точка из книги судна"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
                            ComboBox {
                                id: pivotPresetBox; Layout.fillWidth: true; implicitHeight: 32; textRole: "name"; font.pixelSize: Theme.fsSmall
                                model: [{name: "Мидель", x: 0, y: 0}].concat(core.hull.pivotPresets || [])
                                onActivated: {
                                    const p = model[currentIndex]
                                    pivotXIn.text = String(p.x).replace(".", ",")
                                    pivotYIn.text = String(p.y).replace(".", ",")
                                }
                            }
                            GridLayout {
                                columns: 2; columnSpacing: 8; rowSpacing: 5; Layout.fillWidth: true
                                Label { text: "Вдоль, м (+ нос)"; color: Theme.text; font.pixelSize: Theme.fsSmall; Layout.fillWidth: true }
                                TextField { id: pivotXIn; text: "0"; implicitWidth: 100; implicitHeight: 30; font.family: Theme.mono }
                                Label { text: "Поперёк, м (+ ПрБ)"; color: Theme.text; font.pixelSize: Theme.fsSmall; Layout.fillWidth: true }
                                TextField { id: pivotYIn; text: "0"; implicitWidth: 100; implicitHeight: 30; font.family: Theme.mono }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                ConfirmBtn { label: "Применить центр"; cmd: "pivot " + pivotXIn.text.replace(",", ".") + " " + pivotYIn.text.replace(",", "."); enabled: s.hasShip === true; implicitHeight: 32; Layout.fillWidth: true }
                                ConfirmBtn { label: "Мидель"; cmd: "pivot 0 0"; enabled: s.hasShip === true; implicitHeight: 32; Layout.fillWidth: true }
                            }
                            Label { text: "Допустимо: вдоль ±300 м, поперёк ±100 м. Ядро отклоняет значения вне пределов."; color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            GridLayout {
                                columns: 2; columnSpacing: 8; rowSpacing: 5; Layout.fillWidth: true
                                Label { text: "Поворот, °/мин"; color: Theme.text; font.pixelSize: Theme.fsSmall; Layout.fillWidth: true }
                                TextField { id: rotRateIn; text: "0"; implicitWidth: 100; implicitHeight: 30; font.family: Theme.mono }
                                Label { text: "Скорость, уз"; color: Theme.text; font.pixelSize: Theme.fsSmall; Layout.fillWidth: true }
                                TextField { id: speedRateIn; text: "0"; implicitWidth: 100; implicitHeight: 30; font.family: Theme.mono }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                ConfirmBtn { label: "Задать поворот"; cmd: "rate rot " + rotRateIn.text.replace(",", "."); enabled: s.hasShip === true; implicitHeight: 32; Layout.fillWidth: true }
                                ConfirmBtn { label: "Задать скорость"; cmd: "rate speed " + speedRateIn.text.replace(",", "."); enabled: s.hasShip === true; implicitHeight: 32; Layout.fillWidth: true }
                            }
                            Label { text: "0 — без ограничения. Поворот: 0,5…600 °/мин; скорость: 0,05…30 уз. Каждая команда требует повторного нажатия."; color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true }
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
    }
}
