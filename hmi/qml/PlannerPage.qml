import QtQuick
import QtQuick.Controls

// Планировщик судна: ввод характеристик (корпус, движители, электростанция), схемы энергосистемы и
// движительного комплекса, расчёт и применение к математической модели.
// Правка и расчёт — только у администратора (проверку выполняет ядро). Без входа показывается текущая схема из работающей системы.
// ⚠ Расчёт — оценка по модели ядра (предельный ветер по одним усилиям движителей, баланс мощности по номиналам),
// не расчёт по правилам классификационного общества. Применение к модели происходит при режиме «Ожидание».
Item {
    id: pg
    property var sess: null
    property bool embedded: false          // внутри страницы «Администрирование»: вход выполняется там, один на все вкладки
    readonly property bool isAdmin: sess ? sess.admin : false
    property var prof: null
    property int rev: 0                 // растёт при каждой правке — обновляет схемы и поля
    property bool dirty: false
    property var issues: []
    property var estimates: []
    property var scenarios: []
    property string msg: ""
    property bool msgBad: false
    property int tab: 0
    property real current: 0.5
    readonly property var st: backend.s

    function say(t, bad) { msg = t; msgBad = !!bad }
    function touch() { dirty = true; rev++ }
    function load() {
        if (!sess) return
        sess.send("get", {}, function (r) {
            if (r.ok) { pg.prof = r.profile; pg.issues = r.issues || []; pg.estimates = r.estimates || []; pg.scenarios = []; pg.dirty = false; pg.rev++; pg.say("Профиль загружен", false) }
            else { pg.say(r.err, true); if (r.auth === false) sess.admin = false }
        })
    }
    function check() {
        sess.send("check", { profile: prof }, function (r) {
            pg.issues = r.issues || pg.issues; pg.estimates = r.estimates || pg.estimates
            if (r.ok) pg.say("Проверка пройдена" + (pg.warnCount() > 0 ? ", есть предупреждения" : ""), false)
            else { pg.say(r.err, true); pg.tab = 3 }
        })
    }
    function calc() {
        sess.send("calc", { profile: prof, current: current }, function (r) {
            pg.issues = r.issues || pg.issues
            if (r.ok) { pg.scenarios = r.scenarios || []; pg.estimates = r.estimates || []; pg.say("Расчёт выполнен (течение " + current + " м/с, волна по ветру)", false); pg.tab = 3 }
            else { pg.say(r.err, true); pg.tab = 3 }
        })
    }
    function applyModel() {
        sess.send("set", { profile: prof }, function (r) {
            pg.issues = r.issues || pg.issues; pg.estimates = r.estimates || pg.estimates
            if (r.ok) {
                pg.dirty = false
                pg.say(r.changed === 0 ? "Изменений нет" : "Сохранено (изменено полей: " + r.changed + "). " + (r.pending ? "В модель попадёт, когда судно будет в режиме «Ожидание»." : "Применено."), false)
            } else { pg.say(r.err, true); pg.tab = 3 }
        })
    }
    function warnCount() { var n = 0; for (var i = 0; i < issues.length; ++i) if (!issues[i].error) n++; return n }
    function errCount() { var n = 0; for (var i = 0; i < issues.length; ++i) if (issues[i].error) n++; return n }

    onIsAdminChanged: { if (isAdmin) { if (visible && !prof) load() } else { prof = null; dirty = false } }
    onVisibleChanged: { if (visible && isAdmin && !prof) load() }

    // ---- данные для схем
    function normType(t) { var s = String(t).toLowerCase(); return s.indexOf("азим") >= 0 || s === "azimuth" ? "azimuth" : (s.indexOf("тунн") >= 0 || s === "tunnel" ? "tunnel" : "fixed") }
    readonly property var viewGens: {
        rev
        if (prof && prof.plant) return prof.plant.generators
        var r = []; var g = st.plGens || []
        for (var i = 0; i < g.length; ++i) r.push({ id: g[i].id, ratedKW: g[i].rated, bus: g[i].bus, online: g[i].online })
        return r
    }
    readonly property var viewCons: {
        rev
        var r = []
        if (prof) {
            for (var i = 0; i < prof.thrusters.length; ++i) { var t = prof.thrusters[i]; if (t.powerMaxKW > 0) r.push({ id: t.id, kw: t.powerMaxKW, bus: t.bus === 1 ? "B" : (t.bus === 0 ? "A" : "") }) }
        } else {
            var th = backend.thrusters
            for (var j = 0; j < th.length; ++j) r.push({ id: th[j].id, kw: th[j].powerKW, bus: th[j].bus === 1 ? "B" : "A" })
        }
        return r
    }
    readonly property var viewThr: {
        rev
        var r = []
        if (prof) { for (var i = 0; i < prof.thrusters.length; ++i) { var t = prof.thrusters[i]; r.push({ id: t.id, type: t.type, x: t.x, y: t.y, ang: t.fixedAngleDeg, enabled: t.enabled }) } }
        else { var th = backend.thrusters; for (var j = 0; j < th.length; ++j) r.push({ id: th[j].id, type: normType(th[j].type), x: th[j].x, y: th[j].y, ang: th[j].fixedAngle, enabled: th[j].enabled }) }
        return r
    }

    // ---- поле ввода числа/строки
    component Fld: Item {
        id: f
        property string label: ""
        property string unit: ""
        property var obj: null
        property string key: ""
        property real k: 1
        property bool isStr: false
        height: Theme.px(34); width: parent ? parent.width : 300
        readonly property string shown: { pg.rev; if (!obj || obj[key] === undefined) return ""; return isStr ? String(obj[key]) : String(parseFloat(Number(obj[key] / k).toPrecision(7))) }
        Text { text: f.label; color: Theme.text; font.pixelSize: Theme.px(14); width: Theme.px(210); elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
        TextField {
            id: tf
            x: Theme.px(215); width: Theme.px(f.isStr ? 260 : 110); height: Theme.px(30); anchors.verticalCenter: parent.verticalCenter
            text: f.shown; color: Theme.text; font.pixelSize: Theme.px(14); selectByMouse: true
            horizontalAlignment: f.isStr ? TextInput.AlignLeft : TextInput.AlignRight
            background: Rectangle { color: Theme.panel2; radius: 5; border.color: tf.activeFocus ? Theme.accent : Theme.line }
            onEditingFinished: {
                if (!f.obj) return
                if (f.isStr) { if (f.obj[f.key] !== text) { f.obj[f.key] = text; pg.touch() } return }
                var v = Number(text.replace(",", "."))
                if (isNaN(v)) { text = f.shown; return }
                if (f.obj[f.key] !== v * f.k) { f.obj[f.key] = v * f.k; pg.touch() }
            }
        }
        Text { x: Theme.px(215 + (f.isStr ? 266 : 116)); text: f.unit; color: Theme.sub; font.pixelSize: Theme.px(13); anchors.verticalCenter: parent.verticalCenter }
    }
    component Chk: Item {
        id: c
        property string label: ""
        property var obj: null
        property string key: ""
        height: Theme.px(32); width: parent ? parent.width : 300
        CheckBox { id: cb; checked: { pg.rev; return c.obj ? c.obj[c.key] === true : false } text: c.label
                   contentItem: Text { text: cb.text; color: Theme.text; font.pixelSize: Theme.px(14); leftPadding: cb.indicator.width + 6; verticalAlignment: Text.AlignVCenter }
                   onToggled: { c.obj[c.key] = checked; pg.touch() } }
    }

    // ================================================================= вход
    Rectangle {
        id: loginBox
        visible: !pg.isAdmin && !pg.embedded
        x: 0; y: 0; width: Math.min(parent.width * 0.4, Theme.px(420)); height: loginCol.height + Theme.px(24)
        color: Theme.panel; radius: 8; border.color: Theme.line
        Column {
            id: loginCol; x: Theme.px(12); y: Theme.px(12); width: parent.width - Theme.px(24); spacing: Theme.px(8)
            Text { text: "Планировщик судна"; color: Theme.text; font.pixelSize: Theme.px(18); font.bold: true }
            Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(13)
                   text: "Просмотр схем доступен всем. Ввод характеристик, расчёт и применение к модели — только администратору. Справа показана текущая конфигурация работающей системы." }
            TextField { id: pw; width: parent.width; echoMode: TextInput.Password; placeholderText: "Пароль администратора"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(14)
                        enabled: pg.sess && pg.sess.lockSec <= 0 && pg.sess.pwSet
                        background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line }
                        onAccepted: { pg.sess.login(text); text = "" } }
            Btn { text: "Войти"; active: true; enabledBtn: pg.sess && !pg.sess.busy && pg.sess.pwSet && pg.sess.lockSec <= 0; onClicked: { pg.sess.login(pw.text); pw.text = "" } }
            Text { visible: pg.sess && !pg.sess.pwSet; width: parent.width; wrapMode: Text.Wrap; color: Theme.warn; font.pixelSize: Theme.px(13)
                   text: "Пароль администратора ещё не задан: сначала задайте его в окне «Судно» на компьютере ядра." }
            Text { visible: pg.sess && pg.sess.msg !== ""; width: parent.width; wrapMode: Text.Wrap; color: pg.sess && pg.sess.msgBad ? Theme.bad : Theme.ok; font.pixelSize: Theme.px(13); text: pg.sess ? pg.sess.msg : "" }
        }
    }

    // ================================================================= редактор (администратор)
    Rectangle {
        id: ed
        visible: pg.isAdmin
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: Math.min(parent.width * 0.5, Theme.px(560))
        color: Theme.panel; radius: 8; border.color: Theme.line
        Column {
            anchors { fill: parent; margins: Theme.px(10) }
            spacing: Theme.px(8)
            Row {
                spacing: Theme.px(6); width: parent.width
                Seg { width: parent.width - (pg.embedded ? 0 : Theme.px(96)); px: Theme.px(12); model: ["Судно", "Движители", "Электростанция", "Расчёт"]; current: pg.tab; onPicked: (i) => pg.tab = i }
                Btn { visible: !pg.embedded; text: "Выйти"; onClicked: { pg.sess.logout() } }
            }
            Text { visible: pg.msg !== ""; width: parent.width; wrapMode: Text.Wrap; color: pg.msgBad ? Theme.bad : Theme.ok; font.pixelSize: Theme.px(13); text: pg.msg }
            Text { visible: !pg.prof; color: Theme.sub; font.pixelSize: Theme.px(14); text: "Загрузка профиля…" }

            Flickable {
                id: fl
                visible: !!pg.prof
                width: parent.width; height: parent.height - Theme.px(190)
                contentHeight: stack.height; clip: true; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { }
                Item {
                    id: stack; width: fl.width - Theme.px(12); height: Math.max(p0.height, p1.height, p2.height, p3.height)
                    // ---- 0. судно
                    Column { id: p0; visible: pg.tab === 0; width: parent.width; spacing: Theme.px(2)
                        Fld { label: "Название"; obj: pg.prof ? pg.prof.vessel : null; key: "name"; isStr: true }
                        Fld { label: "Длина (LOA)"; unit: "м"; obj: pg.prof ? pg.prof.vessel : null; key: "length" }
                        Fld { label: "Ширина"; unit: "м"; obj: pg.prof ? pg.prof.vessel : null; key: "beam" }
                        Fld { label: "Осадка"; unit: "м"; obj: pg.prof ? pg.prof.vessel : null; key: "draft" }
                        Fld { label: "Водоизмещение"; unit: "т"; k: 1000; obj: pg.prof ? pg.prof.vessel : null; key: "mass" }
                        Fld { label: "Парусность, нос"; unit: "м²"; obj: pg.prof ? pg.prof.vessel : null; key: "frontalArea" }
                        Fld { label: "Парусность, борт"; unit: "м²"; obj: pg.prof ? pg.prof.vessel : null; key: "lateralArea" }
                        Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(12)
                               text: "Основные характеристики. Полный набор (присоединённые массы, демпфирование, остойчивость, загрузка) — в окне «Судно»; профиль у них общий." }
                    }
                    // ---- 1. движители
                    Column { id: p1; visible: pg.tab === 1; width: parent.width; spacing: Theme.px(8)
                        Row { spacing: 6
                            Btn { text: "+ Тоннельный"; onClicked: pg.addThr("tunnel") }
                            Btn { text: "+ Азимутальный"; onClicked: pg.addThr("azimuth") }
                            Btn { text: "+ Фиксированный"; onClicked: pg.addThr("fixed") }
                        }
                        Repeater {
                            model: { pg.rev; return pg.prof ? pg.prof.thrusters.length : 0 }
                            delegate: Rectangle {
                                id: card
                                required property int index
                                readonly property var t: pg.prof.thrusters[index]
                                width: p1.width; height: cc.height + Theme.px(16); color: Theme.panel2; radius: 6; border.color: Theme.line
                                Column { id: cc; x: 8; y: 8; width: parent.width - 16; spacing: 2
                                    Row { spacing: 6; width: parent.width
                                        Text { text: (card.index + 1) + ". " + card.t.type; color: Theme.accent; font.pixelSize: Theme.px(14); font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - Theme.px(270) }
                                        Btn { text: card.t.bus === 0 ? "Шина A" : card.t.bus === 1 ? "Шина B" : "Шина: —"; px: Theme.px(12)
                                              onClicked: { if (card.t.bus === 0) card.t.bus = 1; else if (card.t.bus === 1) delete card.t.bus; else card.t.bus = 0; pg.touch() } }
                                        Btn { text: "Копия"; px: Theme.px(12); onClicked: pg.copyThr(card.index) }
                                        Btn { text: "Удалить"; px: Theme.px(12); danger: true; onClicked: pg.delThr(card.index) }
                                    }
                                    Fld { width: cc.width; label: "Обозначение"; obj: card.t; key: "id"; isStr: true }
                                    Fld { width: cc.width; label: "Положение x (вперёд)"; unit: "м"; obj: card.t; key: "x" }
                                    Fld { width: cc.width; label: "Положение y (на правый борт)"; unit: "м"; obj: card.t; key: "y" }
                                    Fld { width: cc.width; visible: card.t.type === "fixed"; height: visible ? Theme.px(34) : 0; label: "Направление упора"; unit: "°"; obj: card.t; key: "fixedAngleDeg" }
                                    Fld { width: cc.width; label: "Макс. упор вперёд"; unit: "кН"; k: 1000; obj: card.t; key: "maxForward" }
                                    Fld { width: cc.width; label: "Макс. упор назад"; unit: "кН"; k: 1000; obj: card.t; key: "maxReverse" }
                                    Fld { width: cc.width; label: "Мощность при полном упоре"; unit: "кВт"; obj: card.t; key: "powerMaxKW" }
                                    Chk { width: cc.width; label: "Включён в расчёт"; obj: card.t; key: "enabled" }
                                }
                            }
                        }
                        Text { visible: pg.prof && pg.prof.thrusters.length === 0; color: Theme.warn; font.pixelSize: Theme.px(13); text: "Движители не заданы" }
                    }
                    // ---- 2. электростанция
                    Column { id: p2; visible: pg.tab === 2; width: parent.width; spacing: Theme.px(6)
                        Btn { visible: pg.prof && !pg.prof.plant; text: "Добавить описание электростанции"; active: true
                              onClicked: { pg.prof.plant = { tieClosed: true, tieOpenInDp: true, minReservePct: 15, serviceKW_A: 0, serviceKW_B: 0, generators: [] }; pg.touch() } }
                        Column { visible: pg.prof && !!pg.prof.plant; width: parent.width; spacing: 2
                            Chk { label: "Секционный выключатель замкнут"; obj: pg.prof ? pg.prof.plant : null; key: "tieClosed" }
                            Chk { label: "Разомкнуть в режиме ДП (рекомендуется для класса 2/3)"; obj: pg.prof ? pg.prof.plant : null; key: "tieOpenInDp" }
                            Fld { label: "Минимальный резерв мощности"; unit: "%"; obj: pg.prof ? pg.prof.plant : null; key: "minReservePct" }
                            Fld { label: "Собственные нужды, шина A"; unit: "кВт"; obj: pg.prof ? pg.prof.plant : null; key: "serviceKW_A" }
                            Fld { label: "Собственные нужды, шина B"; unit: "кВт"; obj: pg.prof ? pg.prof.plant : null; key: "serviceKW_B" }
                            Row { spacing: 6; Btn { text: "+ Генератор на шину A"; onClicked: pg.addGen("A") } Btn { text: "+ на шину B"; onClicked: pg.addGen("B") } }
                            Repeater {
                                model: { pg.rev; return pg.prof && pg.prof.plant ? pg.prof.plant.generators.length : 0 }
                                delegate: Rectangle {
                                    id: genCard
                                    required property int index
                                    readonly property var g: pg.prof.plant.generators[index]
                                    width: p2.width; height: gcc.height + 16; color: Theme.panel2; radius: 6; border.color: Theme.line
                                    Column { id: gcc; x: 8; y: 8; width: parent.width - 16; spacing: 2
                                        Row { spacing: 6; width: parent.width
                                            Text { text: "Генератор " + (genCard.index + 1); color: Theme.accent; font.pixelSize: Theme.px(14); font.bold: true; anchors.verticalCenter: parent.verticalCenter; width: parent.width - Theme.px(210) }
                                            Btn { text: "Шина " + genCard.g.bus; px: Theme.px(12); onClicked: { genCard.g.bus = genCard.g.bus === "A" ? "B" : "A"; pg.touch() } }
                                            Btn { text: "Удалить"; px: Theme.px(12); danger: true; onClicked: { pg.prof.plant.generators.splice(genCard.index, 1); pg.touch() } }
                                        }
                                        Fld { width: gcc.width; label: "Обозначение"; obj: genCard.g; key: "id"; isStr: true }
                                        Fld { width: gcc.width; label: "Номинальная мощность"; unit: "кВт"; obj: genCard.g; key: "ratedKW" }
                                        Chk { width: gcc.width; label: "В работе"; obj: genCard.g; key: "online" }
                                    }
                                }
                            }
                        }
                    }
                    // ---- 3. расчёт
                    Column { id: p3; visible: pg.tab === 3; width: parent.width; spacing: Theme.px(6)
                        Text { text: "Замечания"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true }
                        Text { visible: pg.issues.length === 0; text: "Замечаний нет"; color: Theme.ok; font.pixelSize: Theme.px(14) }
                        Repeater { model: pg.issues
                            delegate: Text { required property var modelData; width: p3.width; wrapMode: Text.Wrap; font.pixelSize: Theme.px(13); color: modelData.error ? Theme.bad : Theme.warn
                                             text: (modelData.error ? "Ошибка · " : "Предупреждение · ") + modelData.field + ": " + modelData.text } }
                        Text { text: "Предельный ветер (м/с)"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true; visible: pg.scenarios.length > 0 }
                        Repeater { model: pg.scenarios
                            delegate: Row { required property var modelData; spacing: 10
                                Text { width: Theme.px(250); text: modelData.name; color: Theme.text; font.pixelSize: Theme.px(13); elide: Text.ElideRight }
                                Text { text: "предел " + (modelData.minLimit >= 39.9 ? "> 40" : modelData.minLimit.toFixed(1)); color: Theme.accent; font.pixelSize: Theme.px(13); font.bold: true }
                                Text { text: "рабочий " + (modelData.minWork >= 39.9 ? "> 40" : modelData.minWork.toFixed(1)); color: Theme.sub; font.pixelSize: Theme.px(13) } } }
                        Text { text: "Оценки"; color: Theme.sub; font.pixelSize: Theme.px(13); font.bold: true; visible: pg.estimates.length > 0 }
                        Repeater { model: pg.estimates
                            delegate: Column { required property var modelData; width: p3.width
                                Row { spacing: 8; Text { width: Math.min(p3.width * 0.6, Theme.px(300)); wrapMode: Text.Wrap; text: modelData.label; color: Theme.text; font.pixelSize: Theme.px(13) }
                                      Text { text: modelData.value; color: Theme.accent; font.pixelSize: Theme.px(13); font.bold: true } }
                                Text { visible: modelData.note !== ""; width: parent.width; wrapMode: Text.Wrap; text: modelData.note; color: Theme.sub; font.pixelSize: Theme.px(11) } } }
                    }
                }
            }
            Row {
                visible: !!pg.prof; spacing: Theme.px(6)
                Btn { text: "Проверить"; enabledBtn: !pg.sess.busy; onClicked: pg.check() }
                Btn { text: "Рассчитать"; enabledBtn: !pg.sess.busy; onClicked: pg.calc() }
                Btn { text: pg.dirty ? "Применить к модели ●" : "Применить к модели"; active: pg.dirty; enabledBtn: !pg.sess.busy && pg.errCount() === 0; onClicked: pg.applyModel() }
                Btn { text: "Сбросить"; onClicked: pg.load() }
            }
            Row { visible: !!pg.prof; spacing: 8
                Text { text: "Течение для расчёта, м/с:"; color: Theme.sub; font.pixelSize: Theme.px(13); anchors.verticalCenter: parent.verticalCenter }
                Seg { width: Theme.px(230); px: Theme.px(12); model: ["0", "0,5", "1", "1,5"]; current: pg.current === 0 ? 0 : pg.current === 0.5 ? 1 : pg.current === 1 ? 2 : 3
                      onPicked: (i) => pg.current = [0, 0.5, 1, 1.5][i] }
            }
        }
    }

    // ================================================================= схемы
    Column {
        anchors { left: pg.isAdmin ? ed.right : (pg.embedded ? parent.left : loginBox.right); right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 10 }
        spacing: 10
        Panel {
            width: parent.width; height: (parent.height - 10) * 0.55
            title: "Энергосистема" + (pg.prof ? " · черновик" + (pg.dirty ? " (не применён)" : "") : " · работающая система")
            PowerDiagram {
                anchors.fill: parent
                mode: "power"; gens: pg.viewGens; cons: pg.viewCons
                tie: pg.prof && pg.prof.plant ? pg.prof.plant.tieClosed : true
                serviceA: pg.prof && pg.prof.plant ? pg.prof.plant.serviceKW_A : 0
                serviceB: pg.prof && pg.prof.plant ? pg.prof.plant.serviceKW_B : 0
            }
        }
        Panel {
            width: parent.width; height: (parent.height - 10) * 0.45
            title: "Движительный комплекс" + (pg.prof ? " · черновик" : " · работающая система")
            PowerDiagram {
                anchors.fill: parent
                mode: "prop"; thr: pg.viewThr
                length: pg.prof ? pg.prof.vessel.length : (backend.hullLen > 0 ? backend.hullLen : 60)
                beam: pg.prof ? pg.prof.vessel.beam : (backend.hullBeam > 0 ? backend.hullBeam : 14)
            }
        }
    }

    // ---- правка списков
    function addThr(type) {
        var n = prof.thrusters.length + 1
        prof.thrusters.push({ id: "T" + n, type: type, enabled: true, x: 0, y: 0, z: 0, fixedAngleDeg: type === "fixed" ? 0 : 90,
                              maxForward: 50000, maxReverse: type === "azimuth" ? 50000 : 50000, timeConstS: 2, rateFracPerS: 0.25, azRateDegS: 10, weight: 1, powerMaxKW: 0, forbidden: [] })
        touch()
    }
    function copyThr(i) { var c = JSON.parse(JSON.stringify(prof.thrusters[i])); c.id = c.id + "_2"; c.y = -c.y; prof.thrusters.splice(i + 1, 0, c); touch() }
    function delThr(i) { prof.thrusters.splice(i, 1); touch() }
    function addGen(bus) {
        var n = prof.plant.generators.length + 1
        prof.plant.generators.push({ id: "G" + n, ratedKW: 500, bus: bus, online: true }); touch()
    }
}
