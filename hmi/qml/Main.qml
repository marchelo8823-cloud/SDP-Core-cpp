// Пульт оператора СДП (1920×1080). Макет — холст «Пульт СДП — новый экран» (16.11.2026), замечания операторов K-Pos, Praxis, MT и новичка.
// Шапка всегда говорит правду о состоянии: зелёная — удержание, жёлтая — счисление (с обратным отсчётом), красная — упор снят;
// рядом — последние тревоги с временем и текстом. Слева — план с кругом градусов; в центре — курс, отклонение от точки оператора,
// режимы и задание точки (при отказе — «Что делать»); справа — тревоги, датчики, среда, анализ последствий, журнал;
// внизу — движители (задание и факт) и загрузка за 5 мин.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "."

ApplicationWindow {
    id: win
    width: 1920; height: 1080
    visible: true
    title: "СДП — пульт оператора" + (core.s.shipName ? " — " + core.s.shipName : "")
    color: Theme.bg
    font.family: Theme.font
    font.pixelSize: Theme.fs
    palette.window: Theme.bg; palette.windowText: Theme.text; palette.base: Theme.panel2; palette.text: Theme.text
    palette.button: Theme.panel2; palette.buttonText: Theme.text; palette.highlight: Theme.accent; palette.highlightedText: Theme.bg
    palette.mid: Theme.btnLine; palette.dark: Theme.btnLine; palette.light: Theme.panel2; palette.placeholderText: Theme.dim

    readonly property var s: core.s
    property real step: 1.0          // шаг сдвига точки, м
    property real hstep: 1.0         // шаг курса, °
    property string now: Qt.formatTime(new Date(), "HH:mm:ss")
    Timer { interval: 1000; running: true; repeat: true; onTriggered: win.now = Qt.formatTime(new Date(), "HH:mm:ss") }

    FileDialog { id: shipDlg; title: "Книга данных судна"; nameFilters: ["Книги Excel (*.xlsx)"]; onAccepted: core.loadShip(selectedFile) }
    FileDialog { id: simDlg; title: "Книга имитатора"; nameFilters: ["Книги Excel (*.xlsx)"]; onAccepted: core.simStart(selectedFile) }

    component Panel: Rectangle { color: Theme.panel; radius: 6 }
    component Caption: Label { color: Theme.dim; font.pixelSize: Theme.fsSmall; font.bold: true; font.capitalization: Font.AllUppercase; font.letterSpacing: 1 }
    component Big: Label { color: Theme.text; font.pixelSize: 40; font.family: Theme.mono }
    component Mid: Label { color: Theme.text; font.pixelSize: 26; font.family: Theme.mono }
    component Btn: Button { font.pixelSize: Theme.fs; implicitHeight: 44 }
    component Tag: Rectangle {
        property alias text: tl.text
        property color c: Theme.ok
        radius: 4; color: Theme.tint(c, 0.18); implicitWidth: tl.implicitWidth + 16; implicitHeight: tl.implicitHeight + 6
        Label { id: tl; anchors.centerIn: parent; color: parent.c; font.pixelSize: 12; font.bold: true }
    }
    component Dot: Rectangle { property color c: Theme.ok; implicitWidth: 9; implicitHeight: 9; radius: 5; color: c }

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

    // ------------------------------------------------ состояние для шапки и подсказок
    function mmss(t) { t = Math.max(0, Math.round(t)); return Math.floor(t / 60) + ":" + ("0" + (t % 60)).slice(-2) }
    readonly property bool active: s.stateCode === 3
    readonly property bool hdgCut: active && s.hdgValid === false                 // курса нет, упор снят ядром
    readonly property bool hdgDr: active && s.hdgDR === true && !hdgCut
    readonly property bool posDr: active && s.modeCode === 4 && s.posDR === true
    readonly property var st: {
        if (!s.hasShip) return { label: "НЕТ СУДНА", sub: "Загрузите книгу данных судна", c: Theme.dim }
        if (s.stateCode === 1) return { label: "ЖДУ ДАТЧИКИ", sub: "Нужны курс и положение от датчиков", c: Theme.dim }
        if (s.stateCode === 2) return { label: "ОЖИДАНИЕ", sub: "Движители автоматикой не управляются", c: Theme.accent }
        if (hdgCut) return { label: "УПОР СНЯТ — НЕТ КУРСА", sub: "Гирокомпасов нет " + Theme.num(s.hdgLostS, 0) + " с · автоматика не держит судно", c: Theme.alarm }
        if (hdgDr) return { label: "СЧИСЛЕНИЕ КУРСА", sub: "Нет гирокомпасов · упор будет снят через " + Theme.num(Math.max(0, s.hdgDrS - s.hdgLostS), 1) + " с", c: Theme.warn }
        if (posDr) return { label: "СЧИСЛЕНИЕ ПОЛОЖЕНИЯ", sub: "Нет систем положения " + mmss(s.refLostS) + " · вероятный уход до " + Theme.num(s.drDriftM, 0) + " м", c: Theme.warn }
        if (s.returning) return { label: "ВОЗВРАТ В ТОЧКУ", sub: "До точки " + Theme.num(s.opErr, 1) + " м · «Держать здесь» — остаться", c: Theme.accent }
        if (s.modeCode === 3) return { label: "УДЕРЖАНИЕ КУРСА", sub: "Курс " + Theme.deg(s.refHdg) + " · загрузка " + Theme.num(s.load * 100, 0) + " %", c: Theme.ok }
        return { label: "УДЕРЖАНИЕ ПОЗИЦИИ", sub: "Отклонение " + Theme.num(s.opErr, 1) + " м · курс " + Theme.deg(s.hdg) + " · загрузка " + Theme.num(s.load * 100, 0) + " %", c: Theme.ok }
    }
    readonly property var advice: {
        if (hdgCut) return { c: Theme.alarm, steps: [
            "Возьмите управление: джойстик или посты управления движителями.",
            "Проверьте гирокомпасы: питание, связь.",
            "⚠ Когда курс вернётся, удержание продолжится само — будьте готовы." ] }
        if (hdgDr) return { c: Theme.warn, steps: [
            "Курс держится по счислению, через " + Theme.num(Math.max(0, s.hdgDrS - s.hdgLostS), 1) + " с упор будет снят.",
            "Готовьтесь взять управление вручную.",
            "Проверьте гирокомпасы." ] }
        if (posDr) return { c: Theme.warn, steps: [
            "Судно держится по модели — точность падает с каждой минутой.",
            "Проверьте системы положения. Готовьтесь к ручному управлению. Когда положение вернётся, судно плавно пойдёт в точку; остаться — «Держать здесь»." ] }
        return null
    }
    function levelLetter(l) { return l === 0 ? "E" : l === 1 ? "A" : l === 2 ? "W" : "I" }

    ColumnLayout {
        anchors.fill: parent; anchors.margins: 12; spacing: 12

        // ================================================ шапка
        RowLayout {
            Layout.fillWidth: true; Layout.preferredHeight: 76; spacing: 12
            Rectangle {
                Layout.preferredWidth: 440; Layout.fillHeight: true; radius: 8
                color: Theme.tint(win.st.c, 0.16); border.color: win.st.c; border.width: 2
                ColumnLayout {
                    anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 12; spacing: 2
                    Item { Layout.fillHeight: true }
                    Label { text: win.st.label; color: win.st.c; font.pixelSize: 26; font.bold: true; font.letterSpacing: 1 }
                    Label { text: win.st.sub; color: Theme.text; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true }
                    Item { Layout.fillHeight: true }
                }
            }
            Panel {
                Layout.preferredWidth: 270; Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 6
                    Label { text: s.shipName || "судно не загружено"; color: s.shipName ? Theme.text : Theme.dim; font.pixelSize: 16; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                    RowLayout {
                        spacing: 8
                        Tag { text: s.caClass > 0 ? "DP-" + s.caClass : "класс не задан"; c: s.caClass > 0 ? Theme.ok : Theme.dim }
                        Tag { visible: s.sim === true; text: "ИМИТАЦИЯ ×" + Theme.num(s.simSpeed, 0); c: Theme.warn }
                    }
                }
            }
            Panel {
                Layout.fillWidth: true; Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 6
                    Item { Layout.fillHeight: true }
                    RowLayout {
                        visible: core.alarms.length === 0; spacing: 10
                        Label { text: "✓"; color: Theme.ok; font.pixelSize: 18; font.bold: true }
                        Label { text: "Активных тревог нет"; color: Theme.dim; font.pixelSize: 15 }
                    }
                    Repeater {
                        model: core.alarms.slice(0, 2)
                        delegate: RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            Rectangle {
                                implicitWidth: 22; implicitHeight: 22; radius: 4; color: Theme.levelColor(modelData.level)
                                opacity: modelData.acked || blinkAl.on ? 1 : 0.35
                                Label { anchors.centerIn: parent; text: win.levelLetter(modelData.level); color: Theme.bg; font.bold: true; font.pixelSize: 13 }
                            }
                            Label { text: modelData.time || ""; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 13 }
                            Label { text: modelData.code; color: Theme.levelColor(modelData.level); font.bold: true; font.pixelSize: 14 }
                            Label { text: modelData.text; color: Theme.text; font.pixelSize: 14; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
                Timer { id: blinkAl; interval: 500; repeat: true; running: true; property bool on: true; onTriggered: on = !on }
            }
            Btn { text: "Квитировать"; Layout.preferredWidth: 130; Layout.maximumWidth: 130; Layout.fillHeight: true; font.bold: true; onClicked: core.ack() }
            Panel {
                Layout.preferredWidth: 150; Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 8; spacing: 0
                    Label { text: win.now; color: Theme.text; font.family: Theme.mono; font.pixelSize: 24; Layout.alignment: Qt.AlignRight }
                    Label { text: Qt.formatDate(new Date(), "dd.MM.yyyy"); color: Theme.dim; font.pixelSize: 12; Layout.alignment: Qt.AlignRight }
                }
            }
            ColumnLayout {
                Layout.preferredWidth: 150; Layout.maximumWidth: 150; Layout.fillWidth: false; Layout.fillHeight: true; spacing: 6
                Btn { text: "Судно…"; implicitHeight: 35; Layout.fillWidth: true; font.pixelSize: 13; onClicked: shipDlg.open(); enabled: s.stateCode !== 3 }
                Btn { text: s.sim ? "Стоп имитатор" : "Имитатор…"; implicitHeight: 35; Layout.fillWidth: true; font.pixelSize: 13; enabled: s.hasShip === true && s.stateCode !== 3
                      onClicked: s.sim ? core.command("sim stop") : simDlg.open() }
            }
        }

        // ================================================ середина
        RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true; spacing: 12

            PositionView {
                id: plan
                Layout.fillHeight: true; Layout.preferredWidth: height
                s: core.s; hull: core.hull; thrusters: core.thrusters; track: core.track
            }

            // ------------------------------------------ центр: курс, отклонение, режим, точка / что делать
            ColumnLayout {
                Layout.fillHeight: true; Layout.preferredWidth: 540; Layout.maximumWidth: 540; spacing: 12
                Panel {
                    Layout.fillWidth: true; Layout.preferredHeight: win.hdgDr ? 176 : 142
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; spacing: 6
                        RowLayout {
                            Caption { text: "Курс"; Layout.fillWidth: true }
                            Tag { visible: s.hasShip === true; text: win.hdgCut || !s.hdgValid ? "НЕТ ДАННЫХ" : win.hdgDr ? "ПО СЧИСЛЕНИЮ" : "по гирокомпасам"; c: win.hdgCut || !s.hdgValid ? Theme.alarm : win.hdgDr ? Theme.warn : Theme.ok }
                        }
                        GridLayout {
                            columns: 3; columnSpacing: 18; rowSpacing: 0; Layout.fillWidth: true
                            Big { text: !s.hasShip ? "—" : s.hdgValid ? Theme.deg(s.hdg) : "НЕТ"; color: win.hdgCut ? Theme.alarm : win.hdgDr ? Theme.warn : Theme.text; Layout.preferredWidth: 190 }
                            Mid { text: win.active ? Theme.deg(s.opValid ? s.spHdg : s.refHdg) : "—"; color: Theme.accent; Layout.alignment: Qt.AlignBottom }
                            Mid { text: win.active && s.hdgValid ? Theme.num(s.errHdg, 1) + "°" : "—"; Layout.alignment: Qt.AlignBottom }
                            Label { text: "факт"; color: Theme.dim; font.pixelSize: 12 }
                            Label { text: "задан"; color: Theme.dim; font.pixelSize: 12 }
                            Label { text: "ошибка · поворот " + Theme.num(s.rot, 1) + " °/мин"; color: Theme.dim; font.pixelSize: 12 }
                        }
                        ColumnLayout {
                            visible: win.hdgDr; Layout.fillWidth: true; spacing: 4
                            Rectangle {
                                Layout.fillWidth: true; implicitHeight: 8; radius: 4; color: Theme.line
                                Rectangle { height: parent.height; radius: 4; color: Theme.warn; width: parent.width * Math.max(0, Math.min(1, (s.hdgDrS - s.hdgLostS) / Math.max(0.1, s.hdgDrS))) }
                            }
                            Label { text: "Упор будет снят через " + Theme.num(Math.max(0, s.hdgDrS - s.hdgLostS), 1) + " с, если гирокомпасы не вернутся"; color: Theme.warn; font.pixelSize: 13 }
                        }
                    }
                }
                Panel {
                    Layout.fillWidth: true; Layout.preferredHeight: 158
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 14
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 4
                            Caption { text: "Отклонение от заданной точки" }
                            Big {
                                text: !win.active || s.modeCode !== 4 ? "—" : win.posDr ? "≈ " + Theme.num(s.opErr, 1) + " м" : Theme.num(s.opErr, 1) + " м"
                                color: win.posDr ? Theme.warn : Theme.text
                            }
                            Label {
                                text: win.posDr ? "по модели · измерений нет " + win.mmss(s.refLostS)
                                    : win.active && s.modeCode === 4 ? "вдоль " + (s.opAlong >= 0 ? "+" : "") + Theme.num(s.opAlong, 1) + " м · поперёк " + (s.opCross >= 0 ? "+" : "") + Theme.num(s.opCross, 1) + " м" : "режим «Позиция» не включён"
                                color: win.posDr ? Theme.warn : Theme.text; font.pixelSize: 14
                            }
                            Label {
                                text: win.posDr ? "Вероятный уход до " + Theme.num(s.drDriftM, 0) + " м — точное положение неизвестно" : "Источник: " + (s.posSource || "—")
                                color: win.posDr ? Theme.warn : Theme.dim; font.pixelSize: 13; elide: Text.ElideRight; Layout.fillWidth: true
                            }
                        }
                        // мишень: отклонение в осях судна (нос вверх), масштаб — 10 м до края
                        Canvas {
                            id: eye
                            Layout.preferredWidth: 132; Layout.preferredHeight: 132
                            onPaint: {
                                const g = getContext("2d"); g.reset()
                                const c = width / 2, r = c - 4, k = r / 10
                                g.fillStyle = Theme.plot; g.beginPath(); g.arc(c, c, r, 0, 2 * Math.PI); g.fill()
                                g.strokeStyle = Theme.btnLine; g.lineWidth = 1.5; g.stroke()
                                g.strokeStyle = Theme.line; g.lineWidth = 1
                                g.beginPath(); g.arc(c, c, 5 * k, 0, 2 * Math.PI); g.stroke()
                                g.beginPath(); g.moveTo(c, c - r); g.lineTo(c, c + r); g.moveTo(c - r, c); g.lineTo(c + r, c); g.stroke()
                                g.fillStyle = Theme.dim; g.font = "10px '" + Theme.font + "'"; g.textAlign = "center"; g.fillText("нос", c, 14); g.fillText("5 м", c + 5 * k * 0.72 + 8, c - 5 * k * 0.72)
                                if (!win.active || s.modeCode !== 4) return
                                if (win.posDr && s.drDriftM > 0.2) {
                                    g.strokeStyle = Theme.warn; g.fillStyle = Theme.tint(Theme.warn, 0.12); g.lineWidth = 1.5
                                    g.beginPath(); g.arc(c, c, Math.min(r, s.drDriftM * k), 0, 2 * Math.PI); g.fill(); g.stroke()
                                }
                                const x = Math.max(-r, Math.min(r, s.opCross * k)), y = Math.max(-r, Math.min(r, s.opAlong * k))
                                g.fillStyle = win.posDr ? Theme.warn : Theme.vessel; g.beginPath(); g.arc(c + x, c - y, 6, 0, 2 * Math.PI); g.fill()
                            }
                            Connections { target: core; function onChanged() { eye.requestPaint() } }
                        }
                    }
                }
                Panel {
                    Layout.fillWidth: true; Layout.preferredHeight: win.posLossOrReturn ? 200 : 156
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 14; spacing: 8
                        RowLayout {
                            Caption { text: "Режим"; Layout.fillWidth: true }
                            Label { text: "смена — повторное нажатие за 3 с"; color: Theme.dim; font.pixelSize: 12 }
                        }
                        RowLayout {
                            spacing: 8
                            ConfirmBtn { label: "Ожидание"; cmd: "standby"; highlighted: s.modeCode === 0; Layout.fillWidth: true }
                            ConfirmBtn { label: "Курс"; cmd: "heading"; highlighted: s.modeCode === 3; enabled: s.stateCode >= 2; Layout.fillWidth: true }
                            ConfirmBtn { label: "Позиция"; cmd: "position"; highlighted: s.modeCode === 4; enabled: s.stateCode >= 2; Layout.fillWidth: true }
                        }
                        RowLayout {
                            spacing: 8
                            Label {
                                Layout.fillWidth: true; color: Theme.text; font.pixelSize: 14; elide: Text.ElideRight
                                text: { let n = 0; for (let i = 0; i < core.thrusters.length; ++i) if (core.thrusters[i].taken) ++n
                                        return "Движители: " + n + " из " + core.thrusters.length + " в управлении" + (win.hdgCut ? ", команды 0 %" : "") }
                            }
                            Btn { text: "Взять все"; enabled: s.hasShip === true; onClicked: core.command("thr_take all") }
                            ConfirmBtn { label: "Снять все"; cmd: "thr_release all"; enabled: s.hasShip === true }
                        }
                        Btn { text: "Держать здесь (не возвращаться в точку)"; visible: s.modeCode === 4 && win.posLossOrReturn; Layout.fillWidth: true
                              palette.button: Theme.warn; palette.buttonText: "#1a1a1a"; font.bold: true; onClicked: core.command("here") }
                        Label { color: Theme.dim; font.pixelSize: Theme.fsSmall; wrapMode: Text.Wrap; Layout.fillWidth: true
                                text: win.armedCmd !== "" ? "Нажмите ту же кнопку ещё раз в течение 3 с, чтобы подтвердить." : s.stateCode === 0 ? "Загрузите судно." : s.stateCode === 1 ? "Ядро ждёт курс и положение от датчиков." : s.stateCode === 2 ? "Возьмите движители и включите режим." : "" }
                    }
                }
                // при отказе — что делать; иначе — задание точки и курса
                Rectangle {
                    visible: win.advice !== null
                    Layout.fillWidth: true; Layout.fillHeight: true; radius: 6
                    color: win.advice ? Theme.tint(win.advice.c, 0.14) : "transparent"; border.color: win.advice ? win.advice.c : "transparent"; border.width: 2
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 5
                        Label { text: "ЧТО ДЕЛАТЬ"; color: win.advice ? win.advice.c : Theme.text; font.bold: true; font.pixelSize: 14 }
                        Repeater {
                            model: win.advice ? win.advice.steps : []
                            delegate: RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                Label { text: (index + 1); color: win.advice ? win.advice.c : Theme.text; font.bold: true; font.pixelSize: 14; Layout.alignment: Qt.AlignTop }
                                Label { text: modelData; color: Theme.text; font.pixelSize: 14; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
                Panel {
                    visible: win.advice === null
                    Layout.fillWidth: true; Layout.fillHeight: true
                    enabled: s.stateCode === 3
                    opacity: enabled ? 1 : 0.5
                    RowLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 14
                        GridLayout {
                            columns: 3; rowSpacing: 4; columnSpacing: 6; Layout.alignment: Qt.AlignVCenter
                            Item { width: 1 } Btn { text: "С"; implicitWidth: 56; implicitHeight: 36; onClicked: core.command("move " + step + " 0") } Item { width: 1 }
                            Btn { text: "З"; implicitWidth: 56; implicitHeight: 36; onClicked: core.command("move 0 " + (-step)) }
                            Label { text: "+"; color: Theme.accent; font.pixelSize: 22; Layout.alignment: Qt.AlignCenter }
                            Btn { text: "В"; implicitWidth: 56; implicitHeight: 36; onClicked: core.command("move 0 " + step) }
                            Item { width: 1 } Btn { text: "Ю"; implicitWidth: 56; implicitHeight: 36; onClicked: core.command("move " + (-step) + " 0") } Item { width: 1 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 6; Layout.alignment: Qt.AlignVCenter
                            RowLayout {
                                spacing: 6
                                Caption { text: "Точка и курс"; Layout.fillWidth: true }
                                ComboBox { model: ["1 м", "5 м", "10 м"]; onActivated: step = [1, 5, 10][currentIndex]; implicitWidth: 84; implicitHeight: 34; font.pixelSize: 13 }
                                ComboBox { model: ["1°", "5°", "10°"]; onActivated: hstep = [1, 5, 10][currentIndex]; implicitWidth: 74; implicitHeight: 34; font.pixelSize: 13 }
                            }
                            RowLayout {
                                spacing: 6
                                Btn { text: "Курс −" + hstep + "°"; implicitHeight: 36; Layout.fillWidth: true; onClicked: core.command("move 0 0 " + (-hstep)) }
                                Btn { text: "Курс +" + hstep + "°"; implicitHeight: 36; Layout.fillWidth: true; onClicked: core.command("move 0 0 " + hstep) }
                            }
                            Btn { text: "Точка = здесь"; implicitHeight: 36; Layout.fillWidth: true
                                  onClicked: core.command("set " + s.n.toFixed(2) + " " + s.e.toFixed(2) + " " + s.hdg.toFixed(1)) }
                        }
                    }
                }
            }

            // ------------------------------------------ справа: тревоги, датчики, среда, анализ последствий, журнал
            ColumnLayout {
                Layout.fillHeight: true; Layout.fillWidth: true; spacing: 12
                Panel {
                    Layout.fillWidth: true; Layout.preferredHeight: 150
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 6
                        Caption { text: "Тревоги (" + core.alarms.length + ")" }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: 4
                            model: core.alarms
                            delegate: Rectangle {
                                width: ListView.view.width; height: alr.implicitHeight + 10; radius: 4
                                color: Theme.tint(Theme.levelColor(modelData.level), modelData.acked ? 0.10 : 0.22)
                                border.color: Theme.levelColor(modelData.level); border.width: modelData.acked ? 1 : 2
                                RowLayout {
                                    id: alr; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: 6; spacing: 8
                                    Label { text: modelData.time || ""; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 12; Layout.alignment: Qt.AlignTop }
                                    Label { text: "<b>" + modelData.code + "</b>  " + modelData.text; textFormat: Text.StyledText; color: Theme.text; font.pixelSize: 13; wrapMode: Text.Wrap; Layout.fillWidth: true }
                                }
                            }
                            Label { visible: core.alarms.length === 0; text: "Тревог нет"; color: Theme.ok; anchors.centerIn: parent }
                        }
                    }
                }
                Panel {
                    Layout.fillWidth: true; Layout.preferredHeight: 196
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 12; spacing: 6
                        Caption { text: "Датчики и системы положения" }
                        GridLayout {
                            Layout.fillWidth: true; columns: 2; columnSpacing: 18; rowSpacing: 2
                            Repeater {
                                model: core.sensors
                                delegate: RowLayout {
                                    Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 8; implicitHeight: 22
                                    readonly property color sc: !modelData.valid ? Theme.alarm : modelData.rejected ? Theme.warn : Theme.ok
                                    Dot { c: sc }
                                    Label { text: modelData.id; color: Theme.text; font.bold: true; Layout.preferredWidth: 62; font.pixelSize: 13 }
                                    Label { text: !modelData.valid ? "нет данных" : modelData.rejected ? "отбракована" + (modelData.state ? ": " + modelData.state : "") : modelData.kind
                                            color: modelData.valid && !modelData.rejected ? Theme.dim : sc; Layout.fillWidth: true; font.pixelSize: 13; elide: Text.ElideRight }
                                    Label { text: modelData.age >= 0 ? Theme.num(modelData.age, 1) + " с" : "—"; color: Theme.dim; font.pixelSize: 12; font.family: Theme.mono }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
                RowLayout {
                    Layout.fillWidth: true; Layout.preferredHeight: 200; Layout.maximumHeight: 200; Layout.fillHeight: false; spacing: 12
                    Panel {
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                        GridLayout {
                            anchors.fill: parent; anchors.margins: 12; columns: 2; rowSpacing: 6; columnSpacing: 10
                            Caption { text: "Среда"; Layout.columnSpan: 2 }
                            Label { text: "Ветер, откуда"; color: Theme.dim; font.pixelSize: 13 }
                            Label { text: s.windValid ? Theme.num(s.windSpeed, 1) + " м/с · " + Theme.num((s.windFromRel + s.hdg) % 360, 0) + "°" : "НЕТ"; color: s.windValid ? Theme.wind : Theme.warn; font.family: Theme.mono; font.pixelSize: 14; Layout.alignment: Qt.AlignRight }
                            Label { text: "Ветер от носа"; color: Theme.dim; font.pixelSize: 13 }
                            Label { text: s.windValid ? Theme.num(s.windFromRel > 180 ? 360 - s.windFromRel : s.windFromRel, 0) + "° " + (s.windFromRel > 180 ? "лев." : "пр.") + " борта" : "—"; color: Theme.text; font.family: Theme.mono; font.pixelSize: 14; Layout.alignment: Qt.AlignRight }
                            Label { text: "Возмущение, откуда"; color: Theme.dim; font.pixelSize: 13 }
                            Label { text: !s.hasShip ? "—" : Theme.num(Math.sqrt(s.distN * s.distN + s.distE * s.distE) / 1000, 0) + " кН · " + Theme.num((Math.atan2(s.distE, s.distN) * 180 / Math.PI + 540) % 360, 0) + "°"; color: Theme.dist; font.family: Theme.mono; font.pixelSize: 14; Layout.alignment: Qt.AlignRight }
                            Label { text: "Волнение (по качке)"; color: Theme.dim; font.pixelSize: 13 }
                            Label { text: s.waveHs >= 0 ? Theme.num(s.waveHs, 1) + " м" : "не оценено"; color: Theme.text; font.family: Theme.mono; font.pixelSize: 14; Layout.alignment: Qt.AlignRight }
                            Label { text: "Крен / дифферент"; color: Theme.dim; font.pixelSize: 13 }
                            Label { text: Theme.num(s.roll, 1) + "° / " + Theme.num(s.pitch, 1) + "°"; color: Theme.text; font.family: Theme.mono; font.pixelSize: 14; Layout.alignment: Qt.AlignRight }
                            Item { Layout.fillHeight: true; Layout.columnSpan: 2 }
                        }
                    }
                    Panel {
                        Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: 1
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 5
                            Caption { text: "Анализ последствий отказа" }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Btn { text: "Класс 2"; implicitHeight: 30; Layout.fillWidth: true; highlighted: s.caClass === 2; enabled: s.hasShip === true; onClicked: core.command("class 2") }
                                Btn { text: "Класс 3"; implicitHeight: 30; Layout.fillWidth: true; highlighted: s.caClass === 3; enabled: s.hasShip === true; onClicked: core.command("class 3") }
                                Btn { text: "Выкл"; implicitHeight: 30; Layout.fillWidth: true; highlighted: s.caClass === 0; enabled: s.hasShip === true; onClicked: core.command("class off") }
                            }
                            Label { Layout.fillWidth: true; wrapMode: Text.Wrap; font.pixelSize: 13
                                    color: s.caClass === 0 ? Theme.dim : s.caAlarm ? Theme.alarm : s.caRan ? Theme.ok : Theme.dim
                                    text: s.caClass === 0 ? "Выключен. Для DYNPOS-2/3 включите класс (РС ч. XV 8.9.5)."
                                        : !s.caRan ? "Класс " + s.caClass + ": расчёт через 60 с в режиме «Позиция» при неизменных точке и курсе."
                                        : (s.caAlarm ? "НЕ ХВАТИТ упора при наихудшем отказе" : "Запас есть при наихудшем отказе") + " (" + Theme.num(s.caAge, 0) + " с назад)"
                                          + (s.caSingle ? " · группы не заданы — одиночные отказы" : "") }
                            Repeater {
                                model: s.caGroups
                                delegate: ColumnLayout {
                                    Layout.fillWidth: true; spacing: 2
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label { text: "отказ " + modelData.name; color: Theme.text; Layout.fillWidth: true; font.pixelSize: 12; elide: Text.ElideRight }
                                        Label { text: Theme.num(modelData.force, 0) + " / " + Theme.num(modelData.moment, 0) + " %"; color: modelData.holds ? Theme.dim : Theme.alarm; font.pixelSize: 12; font.family: Theme.mono }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true; implicitHeight: 5; radius: 3; color: Theme.line
                                        Rectangle { height: parent.height; radius: 3; width: parent.width * Math.min(modelData.force, modelData.moment) / 100; color: modelData.alarm ? Theme.alarm : modelData.holds ? Theme.ok : Theme.warn }
                                    }
                                }
                            }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
                Panel {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    ColumnLayout {
                        anchors.fill: parent; anchors.margins: 10; spacing: 6
                        Caption { text: "Журнал событий" }
                        ListView {
                            Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                            model: core.log
                            delegate: Label { text: modelData; color: modelData.indexOf("ТРЕВОГА") >= 0 ? Theme.warn : Theme.dim; font.pixelSize: 12; font.family: Theme.mono; width: ListView.view.width; elide: Text.ElideRight }
                        }
                        TextField { id: cmd; Layout.fillWidth: true; implicitHeight: 34; placeholderText: "команда ядра (help — список)"; font.family: Theme.mono; font.pixelSize: 13
                                    onAccepted: { core.command(text); text = "" } }
                    }
                }
            }
        }

        // ================================================ движители и загрузка
        RowLayout {
            Layout.fillWidth: true; Layout.preferredHeight: 214; spacing: 12
            Repeater {
                model: core.thrusters
                delegate: ThrusterTile { t: modelData; cut: win.hdgCut; Layout.fillWidth: true; Layout.fillHeight: true; Layout.maximumWidth: 380 }
            }
            Panel {
                visible: core.thrusters.length === 0; Layout.fillWidth: true; Layout.fillHeight: true
                Label { text: "Движители появятся после загрузки судна"; color: Theme.dim; anchors.centerIn: parent }
            }
            Item { Layout.fillWidth: true; visible: core.thrusters.length > 0 && core.thrusters.length < 4 }
            Panel {
                Layout.preferredWidth: 360; Layout.fillHeight: true
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 12; spacing: 4
                    RowLayout {
                        Caption { text: "Загрузка за 5 мин"; Layout.fillWidth: true }
                        Label { text: Theme.num(s.powerKW, 0) + " кВт"; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 13 }
                    }
                    Label { text: Theme.num(s.load * 100, 0) + " %"; color: s.load > 0.8 ? Theme.alarm : Theme.text; font.family: Theme.mono; font.pixelSize: 32 }
                    Canvas {
                        id: spark
                        Layout.fillWidth: true; Layout.fillHeight: true
                        onPaint: {
                            const g = getContext("2d"); g.reset()
                            const W = width, H = height, h = s.loadHist || []
                            const y = function (v) { return H - 2 - Math.max(0, Math.min(1, v)) * (H - 4) }
                            g.strokeStyle = Theme.alarm; g.globalAlpha = 0.6; g.setLineDash([4, 4]); g.lineWidth = 1
                            g.beginPath(); g.moveTo(0, y(0.8)); g.lineTo(W, y(0.8)); g.stroke(); g.setLineDash([]); g.globalAlpha = 1
                            if (h.length < 2) return
                            g.strokeStyle = Theme.accent; g.lineWidth = 2; g.beginPath()
                            for (let i = 0; i < h.length; ++i) { const x = W - (h.length - 1 - i) * W / 149; if (i === 0) g.moveTo(x, y(h[i])); else g.lineTo(x, y(h[i])) }
                            g.stroke()
                        }
                        Connections { target: core; function onChanged() { spark.requestPaint() } }
                    }
                    Label { text: "красная линия — 80 %"; color: Theme.dim; font.pixelSize: 12 }
                }
            }
        }
    }
}
