// Опорные системы: только отображение состояния Estimator и последних показаний SensorHub.
// Четыре группы — положение, курс, качка и ветер; источники решения не выбираются этим экраном.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "."

Item {
    id: root
    property var sensors: []
    property var summary: ({})
    readonly property int cardCount: 4
    readonly property int rowCount: sensors.length
    readonly property int validCount: sensors.filter(function(d) { return d.valid }).length
    readonly property int failedCount: sensors.filter(function(d) { return !d.valid }).length
    readonly property int warningCount: sensors.filter(isWarning).length

    function isWarning(d) {
        return d.valid && ((d.state && d.state !== "OK" && d.state !== "OFF") || (d.kind === "курс" && Math.abs(d.dHdg || 0) > 1))
    }
    function sensorColor(d) {
        if (!d.valid) return Theme.alarm
        if (d.state === "OFF") return Theme.dim
        return isWarning(d) ? Theme.warn : Theme.ok
    }
    function stateText(d) {
        if (!d.valid) return "НЕТ ДАННЫХ"
        const states = {
            "": "НОРМА", "OK": "НОРМА", "OFF": "ОТКЛЮЧЁН", "STALE": "УСТАРЕЛ",
            "PRED": "ОТКЛОНЁН", "MEDIAN": "МЕДИАНА", "MEDIANW": "РАСХОЖДЕНИЕ",
            "MONITOR": "НАБЛЮДЕНИЕ", "MOBILE": "МОБИЛЬНЫЙ", "FROZEN": "ЗАМОРОЖЕН", "JUMP": "СКАЧОК"
        }
        return states[d.state || ""] || d.state
    }
    function isUsed(d) {
        if (d.kind !== "положение") return false
        return String(summary.posSource || "").split("+").indexOf(d.id) >= 0
    }
    function reading(d) {
        if (!d.valid) return "Нет свежих показаний"
        if (d.kind === "курс") return Theme.hdg3(d.hdgDeg)
        if (d.kind === "ветер") return Theme.bearing(d.windFromRel) + "  ·  " + Theme.num(Theme.knots(d.windMs), 1) + " уз"
        if (d.kind === "качка") return "Крен " + Theme.num(Math.abs(d.roll), 1) + "° " + (d.roll < 0 ? "ЛБ" : "ПрБ")
        if (d.kind === "положение") {
            if (d.gnssQ !== undefined && d.gnssQ >= 0) {
                const q = d.gnssQ === 2 ? "DGPS" : d.gnssQ === 4 ? "RTK fixed" : d.gnssQ === 5 ? "RTK float" : "GPS"
                return q + (d.gnssSats >= 0 ? "  ·  " + d.gnssSats + " сп." : "") + (d.gnssHdop >= 0 ? "  ·  HDOP " + Theme.num(d.gnssHdop, 1) : "")
            }
            return d.sdRep > 0 ? "Положение  ·  σ " + Theme.num(d.sdRep, 2) + " м" : "Показания положения приняты"
        }
        return "Показания приняты"
    }
    function details(d) {
        if (!d.valid) return d.age >= 1 ? "Возраст последних данных: " + Theme.num(d.age, 1) + " с" : "Показания ещё не поступали"
        let t = ""
        if (d.kind === "курс") {
            const dd = d.dHdg || 0
            t = "Δ " + (Math.abs(dd) < 0.05 ? "0,0" : (dd > 0 ? "+" : "") + Theme.num(dd, 1)) + "° от решения"
        } else if (d.kind === "ветер") t = "От носа · кажущийся ветер"
        else if (d.kind === "качка") t = "Дифферент " + Theme.num(d.pitch, 1) + "°"
        else if (d.kind === "положение") {
            if (d.gnssQ !== undefined && d.gnssQ >= 0 && d.sdRep > 0) t = "Повторяемость σ " + Theme.num(d.sdRep, 2) + " м"
            else t = d.gnssQ !== undefined && d.gnssQ >= 0 ? "Качество спутникового решения" : "Повторяемость измерений"
        }
        if (d.rejected > 0) t += (t ? "  ·  " : "") + "отклонений: " + d.rejected
        return t
    }

    component SolutionCard: Rectangle {
        property string title: ""
        property string value: ""
        property string detail: ""
        property color statusColor: Theme.dim
        Layout.fillWidth: true
        implicitHeight: 68
        radius: 3
        color: Theme.panel2
        border.color: Theme.line
        RowLayout {
            anchors.fill: parent; anchors.margins: 9; spacing: 8
            Rectangle { implicitWidth: 4; Layout.fillHeight: true; color: parent.parent.statusColor; radius: 2 }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 1
                Label { text: title; color: Theme.dim; font.pixelSize: 11; font.letterSpacing: 1 }
                Label { text: value; color: Theme.text; font.pixelSize: 18; font.bold: true; font.family: Theme.mono; elide: Text.ElideRight; Layout.fillWidth: true }
                Label { text: detail; color: Theme.dim; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
            }
        }
    }

    component SensorGroup: Rectangle {
        property string title: ""
        property var rows: []
        property string solution: ""
        property color statusColor: Theme.dim
        Layout.fillWidth: true; Layout.fillHeight: true
        implicitHeight: 175
        radius: 3
        color: Theme.bg
        border.color: Theme.line
        clip: true
        ColumnLayout {
            anchors.fill: parent; anchors.margins: 9; spacing: 5
            RowLayout {
                Layout.fillWidth: true; spacing: 7
                Rectangle { implicitWidth: 9; implicitHeight: 9; radius: 5; color: statusColor }
                Label { text: title; color: Theme.text; font.pixelSize: 15; font.bold: true }
                Label { text: rows.length + " датч."; color: Theme.dim; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Label { text: solution; color: statusColor; font.pixelSize: 11; elide: Text.ElideRight; Layout.maximumWidth: 410 }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line }
            ListView {
                Layout.fillWidth: true; Layout.fillHeight: true
                model: rows; clip: true; spacing: 2
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                    width: ListView.view.width; height: 49
                    color: index % 2 ? "transparent" : Theme.panel
                    radius: 2
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 5; anchors.rightMargin: 5; spacing: 8
                        Rectangle { implicitWidth: 9; implicitHeight: 9; radius: 5; color: root.sensorColor(modelData) }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Label { text: modelData.id; color: Theme.text; font.pixelSize: 14; font.bold: true; font.family: Theme.mono }
                                Rectangle {
                                    visible: root.isUsed(modelData); implicitWidth: usedLabel.implicitWidth + 10; implicitHeight: 17
                                    radius: 2; color: Theme.ok
                                    Label { id: usedLabel; anchors.centerIn: parent; text: "В РЕШЕНИИ"; color: Theme.bg; font.pixelSize: 9; font.bold: true }
                                }
                                Item { Layout.fillWidth: true }
                            }
                            Label { text: root.reading(modelData); color: modelData.valid ? Theme.text : Theme.alarm; font.pixelSize: 13; font.family: Theme.mono; elide: Text.ElideRight; Layout.fillWidth: true }
                            Label { text: root.details(modelData); color: Theme.dim; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        Label {
                            text: root.stateText(modelData) + (modelData.valid && modelData.age >= 1 ? "\n" + Theme.num(modelData.age, 1) + " с" : "")
                            color: root.sensorColor(modelData); font.pixelSize: 10; horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: 92; Layout.alignment: Qt.AlignVCenter
                        }
                    }
                }
                Label { visible: rows.length === 0; anchors.centerIn: parent; text: "Датчики этой группы не настроены"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent; spacing: 9
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 0
                Label { text: "Опорные системы"; color: Theme.text; font.pixelSize: 19; font.bold: true }
                Label { text: "Показания датчиков и источники решения оценщика"; color: Theme.dim; font.pixelSize: Theme.fsSmall }
            }
            Item { Layout.fillWidth: true }
            Label { text: validCount + " / " + rowCount + " активны"; color: Theme.text; font.pixelSize: Theme.fs; font.family: Theme.mono }
            Rectangle {
                implicitWidth: overallLabel.implicitWidth + 18; implicitHeight: 28; radius: 3
                color: failedCount ? Theme.alarm : warningCount ? Theme.warn : Theme.ok
                Label {
                    id: overallLabel; anchors.centerIn: parent
                    text: failedCount ? "НЕТ ДАННЫХ: " + failedCount : warningCount ? "ВНИМАНИЕ: " + warningCount : "ВСЕ В НОРМЕ"
                    color: Theme.bg; font.pixelSize: 11; font.bold: true
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: 7
            SolutionCard {
                title: "ПОЛОЖЕНИЕ"
                value: summary.posDR ? "СЧИСЛЕНИЕ" : summary.posValid ? (summary.posSource || "РЕШЕНИЕ") : "НЕТ ДАННЫХ"
                detail: "СКО решения " + Theme.num(summary.posSigma, 2) + " м" + (summary.gnssDisagree ? " · расхождение систем" : "")
                statusColor: !summary.posValid ? Theme.alarm : summary.posDR || summary.gnssDisagree ? Theme.warn : Theme.ok
            }
            SolutionCard {
                title: "КУРС"
                value: summary.hdgValid ? Theme.hdg3(summary.hdg) : "НЕТ ДАННЫХ"
                detail: summary.hdgDR ? "Счисление · нет данных " + Theme.num(summary.hdgLostS, 0) + " с" : summary.gyroDisagree ? "Расхождение гирокомпасов" : "По данным гирокомпасов"
                statusColor: !summary.hdgValid ? Theme.alarm : summary.hdgDR || summary.gyroDisagree ? Theme.warn : Theme.ok
            }
            SolutionCard {
                title: "КАЧКА / MRU"
                value: summary.mruValid ? Theme.num(Math.abs(summary.roll), 1) + "° / " + Theme.num(summary.pitch, 1) + "°" : "НЕТ ДАННЫХ"
                detail: summary.mruValid ? "В согласии: " + (summary.mruCount || 0) + " · верт. " + Theme.num(summary.heave, 2) + " м" : "Нет согласованных показаний MRU"
                statusColor: !summary.mruValid ? Theme.alarm : summary.mruDisagree ? Theme.warn : Theme.ok
            }
            SolutionCard {
                title: "ВЕТЕР"
                value: summary.windValid ? Theme.num(Theme.knots(summary.windSpeed), 1) + " уз" : "НЕТ ДАННЫХ"
                detail: summary.windValid ? Theme.bearing(summary.windFromRel) + " от носа · решение" : "Решение по ветру недоступно"
                statusColor: summary.windValid ? Theme.ok : Theme.alarm
            }
        }

        GridLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            columns: 2; columnSpacing: 8; rowSpacing: 8
            SensorGroup {
                title: "Положение · GNSS / LASER"; rows: sensors.filter(function(d) { return d.kind === "положение" })
                solution: summary.posSource ? "В решении: " + summary.posSource : "Источник не выбран"
                statusColor: !summary.posValid ? Theme.alarm : summary.posDR || summary.gnssDisagree ? Theme.warn : Theme.ok
            }
            SensorGroup {
                title: "Курс · GYRO"; rows: sensors.filter(function(d) { return d.kind === "курс" })
                solution: summary.hdgValid ? "Решение: " + Theme.hdg3(summary.hdg) : "Решение недоступно"
                statusColor: !summary.hdgValid ? Theme.alarm : summary.hdgDR || summary.gyroDisagree ? Theme.warn : Theme.ok
            }
            SensorGroup {
                title: "Качка · MRU"; rows: sensors.filter(function(d) { return d.kind === "качка" })
                solution: summary.mruValid ? "Согласовано: " + (summary.mruCount || 0) : "Нет решения"
                statusColor: !summary.mruValid ? Theme.alarm : summary.mruDisagree ? Theme.warn : Theme.ok
            }
            SensorGroup {
                title: "Ветер · WIND"; rows: sensors.filter(function(d) { return d.kind === "ветер" })
                solution: summary.windValid ? "Решение: " + Theme.num(Theme.knots(summary.windSpeed), 1) + " уз" : "Нет решения"
                statusColor: summary.windValid ? Theme.ok : Theme.alarm
            }
        }
    }
}
