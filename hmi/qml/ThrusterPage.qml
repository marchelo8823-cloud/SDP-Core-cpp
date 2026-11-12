import QtQuick
import QtQuick.Controls

// Окно «Движители» (по образцу экрана движителей Praxis): оператор берёт движители под управление ДП (по одному или все сразу),
// затем выбирает режим. Зелёное — текущий упор, красная метка — команда ДП, колонка нарисована на своём месте в корме, угол — по струе.
// ⚠ Обороты и нагрузка — оценки по упору (обратной связи по оборотам в ядре нет).
Item {
    id: pg
    readonly property var st: backend.s
    signal openPms()
    readonly property var thr: backend.thrusters || []
    readonly property bool canCmd: st.canControl === true
    readonly property int takenN: { var n = 0; for (var i = 0; i < thr.length; ++i) if (thr[i].taken) ++n; return n }

    // ---- порядок и обозначения: колонки слева направо (T1, T2), подруливающие — от кормы к носу (T3, T4 …)
    function isAz(t) { return t.azimuth === true }
    function order() {
        var az = [], tn = []
        for (var i = 0; i < thr.length; ++i) (isAz(thr[i]) ? az : tn).push(i)
        az.sort(function (a, b) { return thr[a].y - thr[b].y })
        tn.sort(function (a, b) { return thr[a].x - thr[b].x })
        return { az: az, tn: tn }
    }
    // Модель повторителей — ЧИСЛО: иначе карточки пересоздавались бы при каждом снимке, кнопки не успевали бы сработать
    function azCount() { return order().az.length }
    function tnCount() { return order().tn.length }
    function azAt(k) { var o = order(); var i = o.az[k]; return i === undefined ? null : { t: thr[i], tag: "T" + (k + 1) } }
    function tnAt(k) { var o = order(); var i = o.tn[k]; return i === undefined ? null : { t: thr[i], tag: "T" + (o.az.length + k + 1) } }
    property real spin: 0
    NumberAnimation on spin { from: 0; to: 360; duration: 1500; loops: Animation.Infinite; running: pg.takenN > 0 && pg.visible }
    function take(t, on) { backend.command((on ? "thr_take " : "thr_release ") + t.id) }

    // ---- оценки второй шкалы
    function rpmPct(t) { var r = 100 * Math.sqrt(Math.min(1, Math.abs(t.pct || 0) / 100)); return t.enabled === false || !t.taken ? 0 : (isAz(t) ? Math.max(15, r) : 100) }   // ПУ с ВРШ: обороты постоянные, меняется только шаг лопастей
    function jet(t) { return ((t.angle || 0) + 180) % 360 }
    function ready(t) { return t.enabled !== false && (t.bus === undefined || t.bus < 0 || true) }

    Rectangle { anchors.fill: parent; radius: 8; color: Theme.panel; border.color: Theme.line }

    // ---- шапка
    Rectangle { id: modeBox; x: Theme.px(16); y: Theme.px(10); width: Theme.px(110); height: Theme.px(40); radius: 4; color: Theme.panel2; border.color: Theme.line
        Text { anchors.centerIn: parent; text: "РЕЖИМ"; color: Theme.sub; font.pixelSize: Theme.px(14); font.bold: true } }
    Text { x: Theme.px(140); y: Theme.px(14); text: pg.takenN > 0 ? "УПРАВЛЕНИЕ ВКЛЮЧЕНО" : "НЕТ УПРАВЛЕНИЯ"; color: pg.takenN > 0 ? Theme.ok : Theme.warn; font.pixelSize: Theme.px(22); font.bold: true }
    Text { x: Theme.px(140); y: Theme.px(40); text: "Движителей под управлением ДП: " + pg.takenN + " из " + pg.thr.length + "   ·   режим: " + (st.modeText || "")
           color: Theme.sub; font.pixelSize: Theme.px(13) }
    Chip { anchors { right: parent.right; top: parent.top; margins: Theme.px(14) } text: "ИМИТАЦИЯ"; tone: Theme.warn; solid: true; visible: st.sim }

    // ---- ячейки
    component TagBox: Rectangle {
        property string tag: ""; property bool on: false
        width: Theme.px(40); height: Theme.px(40); radius: 4
        color: on ? Theme.ok : "#e8e8e8"; border.color: Theme.line
        Text { anchors.centerIn: parent; text: parent.tag; color: parent.on ? "#06210f" : "#333"; font.pixelSize: Theme.px(15); font.bold: true }
    }
    component StatusBox: Rectangle {
        property bool on: false; property bool dis: false
        width: Theme.px(92); height: Theme.px(30); radius: 3; color: "transparent"; border.width: 2
        border.color: dis ? Theme.bad : on ? Theme.ok : Theme.sub
        Text { anchors.centerIn: parent; text: parent.dis ? "ОТКАЗ" : parent.on ? "В УПР. ДП" : "НЕТ УПР."; font.pixelSize: Theme.px(13); font.bold: true
               color: parent.dis ? Theme.bad : parent.on ? Theme.ok : Theme.text }
    }
    component RBox: Rectangle {      // «R» — движитель готов
        property bool on: false
        width: Theme.px(28); height: Theme.px(28); radius: 3; color: "transparent"; border.width: 1; border.color: on ? Theme.ok : Theme.line
        Text { anchors.centerIn: parent; text: "R"; font.pixelSize: Theme.px(14); font.bold: true; color: parent.on ? Theme.ok : Theme.sub }
    }

    // ---- подруливающий: УПОР (линия, красная метка команды, зелёный упор от нуля) и ОБОРОТЫ
    component TunnelRow: Item {
        id: tr
        property var d: null
        readonly property var t: d ? d.t : ({})
        readonly property bool on: t.taken === true && t.enabled !== false
        width: parent ? parent.width : 600; height: Theme.px(92)
        Text { x: 0; y: Theme.px(2); text: "ШАГ ВРШ"; color: Theme.sub; font.pixelSize: Theme.px(14); font.bold: true }
        Item { id: bars; x: Theme.px(88); width: parent.width - Theme.px(88) - Theme.px(330); height: parent.height
            Rectangle { y: Theme.px(10); width: parent.width; height: Theme.px(10); color: Theme.bg; border.color: Theme.line }
            Rectangle { x: parent.width / 2 - 1; y: Theme.px(6); width: 2; height: Theme.px(18); color: Theme.sub }
            Rectangle { y: Theme.px(10); height: Theme.px(10); color: Theme.ok; visible: tr.on
                x: (tr.t.pct || 0) >= 0 ? parent.width / 2 : parent.width / 2 + (tr.t.pct || 0) / 100 * parent.width / 2
                width: Math.abs(tr.t.pct || 0) / 100 * parent.width / 2 }
            Item { visible: tr.on; width: Theme.px(16); height: Theme.px(26)       // красная метка команды ДП
                x: parent.width / 2 + Math.max(-100, Math.min(100, tr.t.cmdPct || 0)) / 100 * parent.width / 2 - width / 2; y: -Theme.px(4)
                Rectangle { x: parent.width / 2 - 1; y: Theme.px(12); width: 2; height: Theme.px(14); color: Theme.bad }
                Rectangle { x: parent.width / 2 - Theme.px(6); y: 0; width: Theme.px(12); height: Theme.px(12); color: Theme.bad; rotation: 45; transformOrigin: Item.Center; scale: 0.8 } }
            Text { x: 0; y: Theme.px(30); text: Math.round(tr.t.pct || 0) + " %"; color: Theme.text; font.pixelSize: Theme.px(14); font.bold: true; font.family: Theme.mono }
        }
        TagBox { x: parent.width - Theme.px(310); y: Theme.px(2); tag: tr.d ? tr.d.tag : ""; on: tr.on }
        StatusBox { x: parent.width - Theme.px(310); y: Theme.px(48); on: tr.on; dis: tr.t.enabled === false }
        Text { x: parent.width - Theme.px(200); y: Theme.px(4); text: tr.t.id || ""; color: Theme.text; font.pixelSize: Theme.px(16); font.bold: true }
        Text { x: parent.width - Theme.px(200); y: Theme.px(28); text: "шина " + (tr.t.bus === 0 ? "A" : tr.t.bus === 1 ? "B" : "—") + " · " + Math.round(tr.t.powerKW || 0) + " кВт"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        RBox { x: parent.width - Theme.px(36); y: Theme.px(2); on: tr.on }
    }

    // ---- колонка (как на фото): статус «ВЫБРАН», кольцо с углом, шкалы «Тяга» и «Обороты» по бокам, винт, кнопка «КОНТРОЛЬ»
    component AzUnit: Item {
        id: au
        property var d: null
        property bool leftSide: true
        readonly property var t: d ? d.t : ({})
        readonly property bool on: t.taken === true && t.enabled !== false
        readonly property bool dis: t.enabled === false
        readonly property color cyan: "#4dd0e1"
        width: Theme.px(300); height: Theme.px(410)
        // верхняя плашка статуса
        Rectangle { x: Theme.px(20); y: 0; width: Theme.px(260); height: Theme.px(34); radius: 4; color: au.on ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.12) : "transparent"
            border.width: 2; border.color: au.dis ? Theme.bad : au.on ? Theme.ok : Theme.sub
            Text { anchors.centerIn: parent; text: au.dis ? "ОТКАЗ" : au.on ? "ВЫБРАН" : "НЕ ВЫБРАН"; font.pixelSize: Theme.px(16); font.bold: true
                   color: au.dis ? Theme.bad : au.on ? Theme.ok : Theme.sub } }
        // метка движителя, шина, мощность, команда
        TagBox { x: Theme.px(20); y: Theme.px(42); tag: au.d ? au.d.tag : ""; on: au.on }
        Text { x: Theme.px(68); y: Theme.px(42); text: (au.t.id || "") + " · шина " + (au.t.bus === 0 ? "A" : au.t.bus === 1 ? "B" : "—"); color: Theme.text; font.pixelSize: Theme.px(14); font.bold: true }
        Text { x: Theme.px(68); y: Theme.px(62); text: Math.round(au.t.powerKW || 0) + " кВт"; color: Theme.sub; font.pixelSize: Theme.px(13); font.family: Theme.mono }
        Text { x: Theme.px(140); y: Theme.px(63); visible: au.on; text: "ком. " + Math.round(au.t.cmdPct || 0) + "% · " + Theme.hdg(((au.t.cmdAngle || 0) + 180) % 360); color: Theme.bad; font.pixelSize: Theme.px(12); font.family: Theme.mono }
        RBox { x: Theme.px(252); y: Theme.px(40); on: au.on }

        // шкала «Тяга» слева (красный треугольник — команда ДП)
        Item { x: Theme.px(14); y: Theme.px(150); width: Theme.px(26); height: Theme.px(150)
            Rectangle { anchors.fill: parent; color: Theme.bg; border.color: Theme.line }
            Rectangle { y: parent.height / 2 - 1; width: parent.width; height: 2; color: Theme.sub }
            Rectangle { x: 3; width: parent.width - 6; color: au.cyan; visible: au.on
                y: (au.t.pct || 0) >= 0 ? parent.height / 2 - (au.t.pct || 0) / 100 * parent.height / 2 : parent.height / 2
                height: Math.abs(au.t.pct || 0) / 100 * parent.height / 2 }
            Rectangle { visible: au.on; x: -Theme.px(11); width: Theme.px(12); height: Theme.px(12); color: Theme.bad; rotation: 45; scale: 0.85
                y: parent.height / 2 - Math.max(-100, Math.min(100, au.t.cmdPct || 0)) / 100 * parent.height / 2 - height / 2 }
        }
        // шкала «Обороты» справа
        Item { x: Theme.px(260); y: Theme.px(150); width: Theme.px(26); height: Theme.px(150)
            Rectangle { anchors.fill: parent; color: Theme.bg; border.color: Theme.line }
            Rectangle { x: 3; width: parent.width - 6; color: au.cyan; y: parent.height - height - 2; height: pg.rpmPct(au.t) / 100 * (parent.height - 4) }
        }
        Text { x: Theme.px(8); y: Theme.px(306); text: "Тяга"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        Text { x: Theme.px(8); y: Theme.px(322); text: Math.round(au.t.pct || 0) + " %"; color: Theme.text; font.pixelSize: Theme.px(17); font.bold: true; font.family: Theme.mono }
        Text { x: Theme.px(292) - width; y: Theme.px(306); text: "Обороты"; color: Theme.sub; font.pixelSize: Theme.px(13) }
        Text { x: Theme.px(292) - width; y: Theme.px(322); text: Math.round(pg.rpmPct(au.t)) + " %"; color: Theme.text; font.pixelSize: Theme.px(17); font.bold: true; font.family: Theme.mono }

        // ---- кольцо: градусные деления, метка носа, указатель направления струи, красный — команда ДП
        Item {
            id: dial
            x: Theme.px(50); y: Theme.px(96); width: Theme.px(200); height: width
            readonly property real rad: width / 2
            readonly property real jet: pg.jet(au.t)
            readonly property real cmdJet: ((au.t.cmdAngle || 0) + 180) % 360
            Rectangle { anchors.fill: parent; radius: width / 2; color: "transparent"; border.width: 2; border.color: Theme.line }
            Repeater { model: 36
                Item { required property int index; x: dial.rad; y: dial.rad; width: 0; height: 0; rotation: index * 10
                    Rectangle { x: -1; y: -dial.rad + 3; width: index % 3 === 0 ? 2 : 1; height: index % 9 === 0 ? Theme.px(14) : index % 3 === 0 ? Theme.px(9) : Theme.px(5); color: Theme.sub } } }
            // нос судна — белый треугольник сверху
            Rectangle { x: dial.rad - Theme.px(7); y: -Theme.px(8); width: Theme.px(14); height: Theme.px(14); rotation: 45; color: Theme.text }
            // команда ДП (красный ромб на кольце)
            Item { visible: au.on; x: dial.rad; y: dial.rad; width: 0; height: 0; rotation: dial.cmdJet
                Rectangle { x: -Theme.px(5); y: -dial.rad - Theme.px(5); width: Theme.px(10); height: Theme.px(10); rotation: 45; color: Theme.bad } }
            // фактическое направление струи (голубая стрелка внутрь кольца)
            Item { x: dial.rad; y: dial.rad; width: 0; height: 0; rotation: dial.jet
                Rectangle { x: -Theme.px(1.5); y: -dial.rad + Theme.px(16); width: Theme.px(3); height: Theme.px(22); color: au.on ? au.cyan : Theme.sub }
                Rectangle { x: -Theme.px(6); y: -dial.rad + Theme.px(12); width: Theme.px(12); height: Theme.px(12); rotation: 45; color: au.on ? au.cyan : Theme.sub } }
            // угол струи
            Text { x: dial.rad - width / 2; y: dial.rad - Theme.px(46); text: Theme.hdg(dial.jet); color: Theme.text; font.pixelSize: Theme.px(30); font.family: Theme.mono }
            // «крылья» — гондола колонки, поворачивается вместе со струёй
            Item { x: dial.rad; y: dial.rad + Theme.px(4); width: 0; height: 0; rotation: 0
                Rectangle { x: -Theme.px(42); y: -Theme.px(5); width: Theme.px(36); height: Theme.px(10); radius: Theme.px(5); color: au.on ? Theme.text : Theme.sub }
                Rectangle { x: Theme.px(6); y: -Theme.px(5); width: Theme.px(36); height: Theme.px(10); radius: Theme.px(5); color: au.on ? Theme.text : Theme.sub } }
            // винт — три лопасти, жёлтый при управлении
            Item { x: dial.rad; y: dial.rad + Theme.px(52); width: 0; height: 0
                Repeater { model: 3
                    Item { required property int index; rotation: index * 120 + (au.on ? pg.spin : 0); width: 0; height: 0
                        Rectangle { x: -Theme.px(6); y: -Theme.px(20); width: Theme.px(12); height: Theme.px(20); radius: Theme.px(6); color: au.on ? Theme.warn : Theme.sub } } }
                Rectangle { x: -Theme.px(4); y: -Theme.px(4); width: Theme.px(8); height: Theme.px(8); radius: Theme.px(4); color: Theme.bg } }
        }
        // кнопка «КОНТРОЛЬ»: принять / снять колонку
        Rectangle { x: Theme.px(20); y: Theme.px(360); width: Theme.px(260); height: Theme.px(40); radius: 4
            color: ma.pressed ? Qt.rgba(1, 1, 1, 0.12) : au.on ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.12) : "transparent"
            border.width: 2; border.color: au.dis ? Theme.line : au.on ? Theme.ok : Theme.sub; opacity: pg.canCmd && !au.dis ? 1 : 0.5
            Text { anchors.centerIn: parent; text: "КОНТРОЛЬ"; font.pixelSize: Theme.px(17); font.bold: true; color: au.on ? Theme.ok : Theme.text }
            MouseArea { id: ma; anchors.fill: parent; enabled: pg.canCmd && !au.dis; onClicked: pg.take(au.t, !au.on) } }
    }

    // ---- размещение
    Column {
        id: topCol
        x: Theme.px(24); y: Theme.px(70); width: parent.width - Theme.px(48); spacing: Theme.px(8)
        Repeater { model: pg.tnCount()      // верхние ряды: старшее T — выше
            TunnelRow { required property int index; width: topCol.width; d: pg.tnAt(pg.tnCount() - 1 - index) } }
    }
    Row {
        id: botRow
        x: Theme.px(24); width: parent.width - Theme.px(48); anchors.bottom: parent.bottom; anchors.bottomMargin: Theme.px(18)
        spacing: pg.azCount() > 1 ? Math.max(Theme.px(10), (width - pg.azCount() * Theme.px(300)) / (pg.azCount() - 1)) : 0
        readonly property real unitW: Theme.px(300)
        Repeater { model: pg.azCount()
            AzUnit { required property int index; d: pg.azAt(index); leftSide: index === 0
                     x: 0 } }
    }
    // кнопки по центру (как на фото)
    Column {
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Theme.px(170) } spacing: Theme.px(10)
        Btn { width: Theme.px(190); text: "ВЫБОР ДВИЖИТЕЛЕЙ"; enabledBtn: pg.canCmd; onClicked: selPop.open() }
        Btn { width: Theme.px(190); text: "СОСТОЯНИЕ ПИТАНИЯ"; onClicked: pg.openPms() }
        Btn { width: Theme.px(190); text: "ПРИНЯТЬ ВСЕ"; enabledBtn: pg.canCmd && pg.takenN < pg.thr.length; onClicked: backend.command("thr_take all") }
    }

    // ---- выбор движителей: по одному или все сразу
    Popup {
        id: selPop
        parent: Overlay.overlay; anchors.centerIn: parent; modal: true; width: Theme.px(560); padding: Theme.px(16)
        background: Rectangle { color: Theme.panel; border.color: Theme.line; radius: 8 }
        Column { width: parent.width; spacing: Theme.px(8)
            Text { text: "ВЫБОР ДВИЖИТЕЛЕЙ"; color: Theme.text; font.pixelSize: Theme.px(18); font.bold: true }
            Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(12)
                   text: "Движители берутся под управление ДП по одному или все сразу. Режимы (Курс, Позиция…) включаются, когда под управлением есть хотя бы один движитель." }
            Repeater { model: pg.thr.length
                Row { required property int index; width: parent.width; spacing: Theme.px(10)
                    readonly property var t: pg.thr[index] || ({})
                    Text { width: Theme.px(150); text: (t.id || "") + (t.azimuth ? " (колонка)" : " (ПУ)"); color: Theme.text; font.pixelSize: Theme.px(15); anchors.verticalCenter: parent.verticalCenter }
                    Text { width: Theme.px(150); text: t.enabled === false ? "ОТКАЗ" : t.taken ? "под управлением" : "не принят"; color: t.enabled === false ? Theme.bad : t.taken ? Theme.ok : Theme.warn; font.pixelSize: Theme.px(14); anchors.verticalCenter: parent.verticalCenter }
                    Btn { text: t.taken ? "Снять" : "Принять"; enabledBtn: pg.canCmd && t.enabled !== false; onClicked: pg.take(t, !t.taken) }
                } }
            Row { spacing: Theme.px(10)
                Btn { text: "Принять все"; enabledBtn: pg.canCmd; onClicked: backend.command("thr_take all") }
                Btn { text: "Снять все"; enabledBtn: pg.canCmd; onClicked: backend.command("thr_release all") }
                Btn { text: "Закрыть"; onClicked: selPop.close() } }
        }
    }
}
