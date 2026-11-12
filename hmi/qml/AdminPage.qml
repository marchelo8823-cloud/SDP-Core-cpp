import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Параметры судна — раздел администратора. Все проверки (пароль, права, значения) выполняет ядро;
// этот экран только показывает данные и отправляет запросы. Без входа администратора данные профиля сюда не приходят.
Popup {
    id: pg
    modal: true; focus: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 24 : 1000, Theme.px(1060))
    height: Math.min(Overlay.overlay ? Overlay.overlay.height - 24 : 700, Theme.px(760))
    padding: 0
    closePolicy: Popup.NoAutoClose
    background: Rectangle { color: Theme.panel; radius: 10; border.color: Theme.line; border.width: 1 }

    // ------------------------------------------------------------ состояние
    property bool pwSet: false
    property bool admin: false
    property bool pending: false
    property real lockSec: 0
    property string msg: ""          // сообщение вверху (результат последней операции)
    property bool msgBad: false
    property var prof: null          // профиль судна (только пока администратор вошёл)
    property bool dirty: false
    property var issues: []
    property var estimates: []
    property var auditLines: []
    property int tab: 0
    property int rid: 1
    property var waiting: ({})
    property bool busy: false

    function send(op, body, cb) {
        var id = rid++
        waiting[id] = cb
        var o = body || {}
        o.t = "adm"; o.op = op; o.id = id
        busy = true
        backend.adminRequest(JSON.stringify(o))
    }
    Connections {
        target: backend
        function onAdminReply(s) {
            var r
            try { r = JSON.parse(s) } catch (e) { return }
            var cb = pg.waiting[r.id]
            if (cb) { delete pg.waiting[r.id]; pg.busy = false; cb(r) }
        }
    }
    function say(text, bad) { msg = text; msgBad = !!bad }
    function applyStatus(r) {
        if (r.pwSet !== undefined) pwSet = r.pwSet
        if (r.admin !== undefined) admin = r.admin
        if (r.pending !== undefined) pending = r.pending
        lockSec = r.lockSec !== undefined ? r.lockSec : 0
    }
    function refreshStatus() {
        send("status", {}, function (r) {
            var was = pg.admin
            pg.applyStatus(r)
            if (pg.admin && !pg.prof && pg.opened) pg.loadProfile()      // вход выполнен на странице «Администрирование»: профиль подгружаем сразу
            if (was && !pg.admin) pg.say("Сеанс администратора закрыт (простой более 10 минут или потеря связи). Войдите снова — несохранённые правки сохранены в окне.", true)
        })
    }
    function loadProfile() {
        send("get", {}, function (r) {
            if (r.ok) { pg.prof = r.profile; pg.issues = r.issues || []; pg.estimates = r.estimates || []; pg.dirty = false }
            else { pg.say(r.err, true); if (r.auth === false) pg.admin = false }
        })
    }
    function doLogin(pw) {
        send("login", { pw: pw }, function (r) {
            pg.applyStatus(r)
            if (r.ok) { pg.admin = true; pg.say("Вход выполнен", false); if (!pg.dirty || !pg.prof) pg.loadProfile() }
            else pg.say(r.err + (r.lockSec > 0 ? ". Повторить можно через " + Math.ceil(r.lockSec) + " с" : ""), true)
        })
    }
    function doSetup(p1, p2) {
        if (p1 !== p2) { say("Пароли не совпадают", true); return }
        send("setup", { pw: p1 }, function (r) {
            pg.applyStatus(r)
            if (r.ok) { pg.pwSet = true; pg.admin = true; pg.say("Пароль администратора задан", false); pg.loadProfile() }
            else pg.say(r.err, true)
        })
    }
    function doCheck() {
        send("check", { profile: prof }, function (r) {
            pg.issues = r.issues || pg.issues; pg.estimates = r.estimates || pg.estimates
            if (r.ok) pg.say("Проверка пройдена" + (pg.countWarn() > 0 ? ", есть предупреждения (вкладка «Проверка»)" : ""), false)
            else { pg.say(r.err, true); if (r.auth === false) pg.admin = false; else pg.tab = 5 }
        })
    }
    function doSave() {
        send("set", { profile: prof }, function (r) {
            pg.issues = r.issues || pg.issues; pg.estimates = r.estimates || pg.estimates
            if (r.ok) {
                pg.dirty = false; pg.pending = r.pending === true
                pg.say(r.changed === 0 ? "Изменений нет" : "Сохранено (изменённых полей: " + r.changed + "). Применится к модели, когда судно будет в режиме ожидания.", false)
            } else { pg.say(r.err, true); if (r.auth === false) pg.admin = false; else pg.tab = 5 }
        })
    }
    function doLogout() {
        send("logout", {}, function (r) { pg.admin = false; pg.prof = null; pg.dirty = false; pg.issues = []; pg.estimates = []; pg.auditLines = [] })
    }
    function loadAudit() {
        send("audit", {}, function (r) { if (r.ok) pg.auditLines = (r.lines || []).slice().reverse(); else pg.say(r.err, true) })
    }
    function countWarn() { var n = 0; for (var i = 0; i < issues.length; ++i) if (!issues[i].error) n++; return n }
    function countErr() { var n = 0; for (var i = 0; i < issues.length; ++i) if (issues[i].error) n++; return n }
    function issueFor(path) {
        var best = null
        for (var i = 0; i < issues.length; ++i) if (issues[i].field === path) { if (!best || issues[i].error) best = issues[i] }
        return best
    }
    function thrPath(i, key) { var t = prof.thrusters[i]; return "thrusters[" + (t.id === "" ? i : t.id) + "]." + key }

    function setVal(group, key, v) {
        if (!prof) return
        prof[group][key] = v
        dirty = true
        profChanged()
    }
    function setThr(i, key, v) { prof.thrusters[i][key] = v; dirty = true; profChanged() }
    function addThruster() {
        var n = prof.thrusters.length + 1
        prof.thrusters.push({ id: "T" + n, type: "tunnel", enabled: true, x: 0, y: 0, z: 0, fixedAngleDeg: 90, maxForward: 50000, maxReverse: 50000, timeConstS: 2, rateFracPerS: 0.25, azRateDegS: 10, weight: 1, powerMaxKW: 0, forbidden: [] })
        dirty = true; profChanged()
    }
    function copyThruster(i) {
        var c = JSON.parse(JSON.stringify(prof.thrusters[i]))
        c.id = c.id + "_2"; c.y = -c.y
        prof.thrusters.splice(i + 1, 0, c)
        dirty = true; profChanged()
    }
    function removeThruster(i) { prof.thrusters.splice(i, 1); dirty = true; profChanged() }

    function fmt(raw, k) {
        if (raw === undefined || raw === null) return ""
        var v = raw / k
        return String(parseFloat(Number(v).toPrecision(7)))
    }
    function forbiddenText(arr) {
        var s = []
        for (var i = 0; i < arr.length; ++i) s.push(arr[i][0] + ":" + arr[i][1])
        return s.join("; ")
    }
    function parseForbidden(t) {
        var res = [], parts = t.split(";")
        for (var i = 0; i < parts.length; ++i) {
            var p = parts[i].trim(); if (p === "") continue
            var ab = p.split(":"); if (ab.length !== 2) return null
            var a = Number(ab[0].replace(",", ".")), b = Number(ab[1].replace(",", "."))
            if (isNaN(a) || isNaN(b)) return null
            res.push([a, b])
        }
        return res
    }

    onOpened: { msg = ""; refreshStatus(); poll.start() ; pg.waitInfo = ""; if (pg.pwSet && pg.admin && !pg.prof) loadProfile() }
    onClosed: poll.stop()
    property string waitInfo: ""
    Timer { id: poll; interval: 3000; repeat: true; onTriggered: { pg.refreshStatus(); if (pg.lockSec > 0) pg.lockSec = Math.max(0, pg.lockSec - 3) } }

    // ------------------------------------------------------------ поле ввода
    component AField: Item {
        id: f
        property string group: "vessel"
        property string key: ""
        property string label: ""
        property string unit: ""
        property real k: 1
        property string use: "м"          // м — идёт в модель, оц — в расчёты/оценки, спр — справочно (в модели не используется)
        property string hint: ""
        property bool isString: false
        property int thr: -1               // индекс движителя, если поле относится к движителю
        readonly property var raw: pg.prof ? (thr >= 0 ? pg.prof.thrusters[thr][key] : pg.prof[group][key]) : undefined
        readonly property string path: thr >= 0 ? pg.thrPath(thr, key) : group + "." + key
        readonly property var issue: pg.issueFor(path)
        readonly property string shown: isString ? (raw === undefined ? "" : String(raw)) : pg.fmt(raw, k)
        implicitWidth: Theme.px(480); implicitHeight: Theme.px(36)
        function commit(t) {
            var v
            if (isString) v = t
            else { v = Number(t.replace(",", ".")); if (t.trim() === "" || isNaN(v)) { tf.text = shown; return } v = v * k }
            if (thr >= 0) pg.setThr(thr, key, v); else pg.setVal(group, key, v)
        }
        Text { id: lb; x: 0; anchors.verticalCenter: parent.verticalCenter; width: Theme.px(235); elide: Text.ElideRight; text: f.label; color: Theme.text; font.pixelSize: Theme.px(14)
               ToolTip.visible: lbMa.containsMouse && f.hint !== ""; ToolTip.text: f.hint; ToolTip.delay: 400
               MouseArea { id: lbMa; anchors.fill: parent; hoverEnabled: true } }
        TextField {
            id: tf
            x: Theme.px(240); width: Theme.px(f.isString ? 175 : 115); height: Theme.px(32); anchors.verticalCenter: parent.verticalCenter
            text: f.shown; color: Theme.text; font.pixelSize: Theme.px(14); selectByMouse: true
            horizontalAlignment: f.isString ? TextInput.AlignLeft : TextInput.AlignRight
            background: Rectangle { color: Theme.panel2; radius: 5; border.width: f.issue ? 2 : 1; border.color: f.issue ? (f.issue.error ? Theme.bad : Theme.warn) : (tf.activeFocus ? Theme.accent : Theme.line) }
            onEditingFinished: f.commit(text)
            ToolTip.visible: f.issue && hovered; ToolTip.text: f.issue ? f.issue.text : ""; ToolTip.delay: 200
        }
        Text { x: Theme.px(240) + tf.width + 6; anchors.verticalCenter: parent.verticalCenter; text: f.unit; color: Theme.sub; font.pixelSize: Theme.px(13) }
        Rectangle {
            x: f.implicitWidth - Theme.px(26); anchors.verticalCenter: parent.verticalCenter; width: Theme.px(22); height: Theme.px(16); radius: 3
            color: "transparent"; border.width: 1; border.color: f.use === "м" ? Theme.ok : f.use === "оц" ? Theme.accent : Theme.sub
            Text { anchors.centerIn: parent; text: f.use === "м" ? "М" : f.use === "оц" ? "О" : "С"; font.pixelSize: Theme.px(10); font.bold: true
                   color: f.use === "м" ? Theme.ok : f.use === "оц" ? Theme.accent : Theme.sub }
            MouseArea { id: tagMa; anchors.fill: parent; hoverEnabled: true }
            ToolTip.visible: tagMa.containsMouse; ToolTip.delay: 200
            ToolTip.text: f.use === "м" ? "М — значение идёт в математическую модель" : f.use === "оц" ? "О — используется в расчётах и оценках (масса по осадке и т. п.)" : "С — справочные сведения, в модели пока не используются"
        }
    }
    component ABool: Item {
        id: b
        property string group: "loading"
        property string key: ""
        property string label: ""
        property string hint: ""
        property int thr: -1
        readonly property var raw: pg.prof ? (thr >= 0 ? pg.prof.thrusters[thr][key] : pg.prof[group][key]) : false
        implicitWidth: Theme.px(480); implicitHeight: Theme.px(36)
        Switch {
            id: sw; x: 0; anchors.verticalCenter: parent.verticalCenter; checked: b.raw === true
            onToggled: { if (b.thr >= 0) pg.setThr(b.thr, b.key, checked); else pg.setVal(b.group, b.key, checked) }
        }
        Text { x: sw.width + 8; anchors.verticalCenter: parent.verticalCenter; text: b.label; color: Theme.text; font.pixelSize: Theme.px(14)
               ToolTip.visible: tma.containsMouse && b.hint !== ""; ToolTip.text: b.hint; ToolTip.delay: 400
               MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true } }
    }
    component Hint: Text { width: parent ? parent.width : 400; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(12) }
    component Sect: Text { color: Theme.accent; font.pixelSize: Theme.px(15); font.bold: true; topPadding: Theme.px(6) }

    // ------------------------------------------------------------ содержимое
    contentItem: Item {
        // ===== вход
        Item {
            id: lock
            anchors.fill: parent; visible: !pg.admin
            Column {
                anchors.centerIn: parent; spacing: Theme.px(12); width: Math.min(parent.width - 40, Theme.px(460))
                Text { text: "Параметры судна"; color: Theme.text; font.pixelSize: Theme.px(24); font.bold: true }
                Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(13)
                       text: "Раздел администратора. Данные судна и пропульсивного комплекса, парусность, осадка и условия загрузки питают математическую модель. Доступ — только по паролю администратора." }
                // пароль не задан, ядро здесь
                Column {
                    visible: !pg.pwSet && backend.coreHere; spacing: Theme.px(8); width: parent.width
                    Text { text: "Первый запуск: задайте пароль администратора"; color: Theme.warn; font.pixelSize: Theme.px(15); font.bold: true }
                    TextField { id: np1; width: parent.width; echoMode: TextInput.Password; placeholderText: "Новый пароль (не короче 8 символов)"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(15)
                                background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line } }
                    TextField { id: np2; width: parent.width; echoMode: TextInput.Password; placeholderText: "Повторите пароль"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(15)
                                background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line }
                                onAccepted: pg.doSetup(np1.text, np2.text) }
                    Btn { text: "Задать пароль"; active: true; enabledBtn: !pg.busy; onClicked: { pg.doSetup(np1.text, np2.text); np1.text = ""; np2.text = "" } }
                    Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(12)
                           text: "Пароль хранится только в виде хеша (PBKDF2-SHA256 с солью) в папке данных на компьютере ядра. Восстановить его нельзя: при утрате пароль заменяется на компьютере ядра командой sdp_core --set-admin-password." }
                }
                Text { visible: !pg.pwSet && !backend.coreHere; width: parent.width; wrapMode: Text.Wrap; color: Theme.warn; font.pixelSize: Theme.px(14)
                       text: "Пароль администратора ещё не задан. Первый пароль задаётся только на компьютере ядра (в его окне или командой sdp_core --set-admin-password), не с удалённого поста." }
                // вход
                Column {
                    visible: pg.pwSet; spacing: Theme.px(8); width: parent.width
                    TextField { id: pwf; width: parent.width; echoMode: TextInput.Password; placeholderText: "Пароль администратора"; placeholderTextColor: Theme.sub; color: Theme.text; font.pixelSize: Theme.px(16); focus: true
                                enabled: pg.lockSec <= 0
                                background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line }
                                onAccepted: { pg.doLogin(text); text = "" } }
                    Row { spacing: 8
                        Btn { text: "Войти"; active: true; enabledBtn: !pg.busy && pg.lockSec <= 0; onClicked: { pg.doLogin(pwf.text); pwf.text = "" } }
                        Btn { text: "Закрыть"; onClicked: pg.close() } }
                    Text { visible: pg.lockSec > 0; width: parent.width; wrapMode: Text.Wrap; color: Theme.bad; font.pixelSize: Theme.px(14)
                           text: "Вход заблокирован после неудачных попыток. Осталось примерно " + Math.ceil(pg.lockSec) + " с." }
                }
                Row { visible: !pg.pwSet; Btn { text: "Закрыть"; onClicked: pg.close() } }
                Text { visible: pg.msg !== ""; width: parent.width; wrapMode: Text.Wrap; text: pg.msg; color: pg.msgBad ? Theme.bad : Theme.ok; font.pixelSize: Theme.px(14) }
            }
        }

        Text { anchors.centerIn: parent; visible: pg.admin && pg.prof === null; text: "Загрузка профиля…"; color: Theme.sub; font.pixelSize: Theme.px(16) }
        // ===== рабочий экран администратора
        ColumnLayout {
            anchors.fill: parent; anchors.margins: Theme.px(14); spacing: Theme.px(8); visible: pg.admin && pg.prof !== null
            RowLayout {
                Layout.fillWidth: true; spacing: Theme.px(8)
                Text { text: "Параметры судна"; color: Theme.text; font.pixelSize: Theme.px(22); font.bold: true }
                Chip { text: "АДМИНИСТРАТОР"; tone: Theme.warn; solid: true }
                Chip { visible: pg.dirty; text: "ЕСТЬ НЕСОХРАНЁННЫЕ ПРАВКИ"; tone: Theme.warn }
                Chip { visible: pg.pending; text: "ЖДЁТ ПРИМЕНЕНИЯ (нужен режим ожидания)"; tone: Theme.accent }
                Item { Layout.fillWidth: true }
                Btn { text: "Проверить"; enabledBtn: !pg.busy; onClicked: pg.doCheck() }
                Btn { text: "Сохранить"; active: true; enabledBtn: !pg.busy; onClicked: pg.doSave() }
                Btn { text: "Пароль…"; onClicked: chpw.open() }
                Btn { text: "«Старший»…"; onClicked: chief.open() }
                Btn { text: "Выйти"; onClicked: { if (pg.dirty) closeAsk.open(); else pg.close() } }
            }
            Text { visible: pg.msg !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; text: pg.msg; color: pg.msgBad ? Theme.bad : Theme.ok; font.pixelSize: Theme.px(14) }
            Seg {
                Layout.fillWidth: true; px: Theme.px(14)
                model: ["Корпус и загрузка", "Парусность", "Динамика", "Движители", "Условия", "Проверка (" + pg.countErr() + " ош., " + pg.countWarn() + " пред.)", "Журнал"]
                current: pg.tab
                onPicked: (i) => { pg.tab = i; if (i === 6) pg.loadAudit() }
            }
            Flickable {
                id: fl
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true; contentWidth: width; contentHeight: pages.height + 20; boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                Item {
                    id: pages
                    width: fl.width - Theme.px(14)
                    height: Math.max(p0.height, p1.height, p2.height, p3.height, p4.height, p5.height, p6.height)

                    // --- 0. корпус и загрузка
                    Column { id: p0; visible: pg.tab === 0; width: parent.width; spacing: Theme.px(2)
                        Hint { text: "Метки справа: М — значение идёт в математическую модель, О — используется в расчётах и оценках, С — справочное (модель пока не использует). Наведите курсор на название или метку — будет подсказка." }
                        Sect { text: "Судно" }
                        Flow { width: parent.width; spacing: Theme.px(14)
                            AField { group: "vessel"; key: "name"; label: "Название"; isString: true; use: "спр" }
                            AField { group: "vessel"; key: "length"; label: "Длина L"; unit: "м"; hint: "Длина между перпендикулярами или по ватерлинии — одинаково во всех расчётах" }
                            AField { group: "vessel"; key: "beam"; label: "Ширина B"; unit: "м" }
                            AField { group: "vessel"; key: "draft"; label: "Осадка (без носа/кормы)"; unit: "м"; hint: "Средняя осадка. Если ниже заданы осадки носом и кормой, берётся их среднее" }
                            AField { group: "vessel"; key: "mass"; label: "Масса (водоизмещение)"; unit: "т"; k: 1000; hint: "Водоизмещение в рассматриваемом состоянии загрузки" }
                            AField { group: "vessel"; key: "gmT"; label: "Поперечная метацентр. высота GM"; unit: "м" }
                            AField { group: "vessel"; key: "gmL"; label: "Продольная метацентр. высота"; unit: "м" }
                            AField { group: "vessel"; key: "waterplaneCoef"; label: "Коэфф. полноты ватерлинии"; unit: "—" }
                        }
                        Sect { text: "Состояние загрузки и осадка" }
                        Flow { width: parent.width; spacing: Theme.px(14)
                            AField { group: "loading"; key: "condition"; label: "Название состояния"; isString: true; use: "спр"; hint: "Например: «В балласте», «С грузом», «Рабочее». Идёт в журнал и на экран" }
                            AField { group: "loading"; key: "draftFwd"; label: "Осадка носом"; unit: "м"; hint: "0 — не задана. Нос и корма задаются вместе" }
                            AField { group: "loading"; key: "draftAft"; label: "Осадка кормой"; unit: "м" }
                            ABool { key: "massFromDraft"; label: "Вычислять массу по осадке"; hint: "Масса = ρ · Cb · L · B · T. Удобно, когда состояние загрузки задаётся осадками" }
                            AField { group: "loading"; key: "blockCoef"; label: "Коэфф. общей полноты Cb"; unit: "—"; use: "оц"; hint: "Для оценки массы; у рабочих судов обычно 0,5…0,8" }
                            AField { group: "loading"; key: "waterDensity"; label: "Плотность воды"; unit: "кг/м³"; use: "оц"; hint: "Морская вода около 1025, пресная 1000. В динамике модели плотность воды постоянна (1025)" }
                        }
                    }
                    // --- 1. парусность
                    Column { id: p1; visible: pg.tab === 1; width: parent.width; spacing: Theme.px(2)
                        Hint { text: "Ветровая нагрузка: F = ½ · ρ_возд · V² · A · C. Площади — проекции надводной части на плоскости «нос» и «борт» при осадке отсчёта. Чем глубже осадка, тем меньше парусность: модель пересчитывает её по осадке отсчёта." }
                        Sect { text: "Площади и коэффициенты" }
                        Flow { width: parent.width; spacing: Theme.px(14)
                            AField { group: "vessel"; key: "frontalArea"; label: "Парусность, нос (вид спереди)"; unit: "м²" }
                            AField { group: "vessel"; key: "lateralArea"; label: "Парусность, борт (вид сбоку)"; unit: "м²" }
                            AField { group: "vessel"; key: "cx"; label: "Коэфф. силы вдоль cx"; unit: "—"; hint: "Используется, если нет таблицы по углам" }
                            AField { group: "vessel"; key: "cy"; label: "Коэфф. силы поперёк cy"; unit: "—" }
                            AField { group: "vessel"; key: "cn"; label: "Коэфф. момента cn"; unit: "—" }
                        }
                        Sect { text: "Поправки на осадку и палубный груз" }
                        Flow { width: parent.width; spacing: Theme.px(14)
                            AField { group: "loading"; key: "refDraft"; label: "Осадка отсчёта парусности"; unit: "м"; hint: "Осадка, при которой измерены площади выше. 0 — поправка по осадке не делается" }
                            AField { group: "loading"; key: "deckFrontal"; label: "Добавка, нос (палубный груз)"; unit: "м²" }
                            AField { group: "loading"; key: "deckLateral"; label: "Добавка, борт (палубный груз)"; unit: "м²" }
                        }
                        Sect { text: "Таблица коэффициентов по углу ветра" }
                        Text { color: Theme.text; font.pixelSize: Theme.px(14)
                               text: pg.prof && pg.prof.vessel.windTable.cx.length > 0 ? "Таблица задана: " + pg.prof.vessel.windTable.cx.length + " точек, шаг " + pg.prof.vessel.windTable.stepDeg + "°. Она имеет приоритет над cx, cy, cn." : "Таблица не задана: используются cx, cy, cn." }
                        Row { spacing: 8
                            Btn { visible: pg.prof && pg.prof.vessel.windTable.cx.length > 0; text: "Удалить таблицу"; danger: true
                                  onClicked: { pg.prof.vessel.windTable = { stepDeg: 10, cx: [], cy: [], cn: [] }; pg.dirty = true; pg.profChanged() } } }
                        Hint { text: "Ввод таблицы (по данным продувок или справочников) пока выполняется в файле настроек; на этом экране её можно только увидеть или удалить." }
                    }
                    // --- 2. динамика
                    Column { id: p2; visible: pg.tab === 2; width: parent.width; spacing: Theme.px(2)
                        Hint { text: "Значение 0 означает «оценить автоматически» по массе и размерам. Если есть данные модельных испытаний или расчёта, введите их — это самый сильный способ улучшить модель." }
                        Sect { text: "Инерция" }
                        Flow { width: parent.width; spacing: Theme.px(14)
                            AField { group: "loading"; key: "yawGyrationFrac"; label: "Радиус инерции по рысканью"; unit: "× L"; hint: "Обычно 0,2…0,3. Если задан, Izz = m·(k·L)²; 0 — Izz берётся ниже" }
                            AField { group: "vessel"; key: "Izz"; label: "Izz (рыскание)"; unit: "т·м²"; k: 1000 }
                            AField { group: "vessel"; key: "Ixx"; label: "Ixx (крен)"; unit: "т·м²"; k: 1000 }
                            AField { group: "vessel"; key: "Iyy"; label: "Iyy (дифферент)"; unit: "т·м²"; k: 1000 }
                        }
                        Sect { text: "Присоединённые массы" }
                        Flow { width: parent.width; spacing: Theme.px(14)
                            AField { group: "vessel"; key: "addSurge"; label: "Вдоль (surge)"; unit: "т"; k: 1000 }
                            AField { group: "vessel"; key: "addSway"; label: "Поперёк (sway)"; unit: "т"; k: 1000 }
                            AField { group: "vessel"; key: "addYaw"; label: "Рыскание (yaw)"; unit: "т·м²"; k: 1000 }
                            AField { group: "vessel"; key: "addHeave"; label: "Вертикаль (heave)"; unit: "т"; k: 1000 }
                            AField { group: "vessel"; key: "addRoll"; label: "Крен (roll)"; unit: "т·м²"; k: 1000 }
                            AField { group: "vessel"; key: "addPitch"; label: "Дифферент (pitch)"; unit: "т·м²"; k: 1000 }
                        }
                        Sect { text: "Линейное демпфирование" }
                        Flow { width: parent.width; spacing: Theme.px(14)
                            AField { group: "vessel"; key: "Xu"; label: "Вдоль Xu"; unit: "кН·с/м"; k: 1000 }
                            AField { group: "vessel"; key: "Yv"; label: "Поперёк Yv"; unit: "кН·с/м"; k: 1000 }
                            AField { group: "vessel"; key: "Nr"; label: "Рыскание Nr"; unit: "кН·м·с"; k: 1000 }
                            AField { group: "vessel"; key: "Zw"; label: "Вертикаль Zw"; unit: "кН·с/м"; k: 1000 }
                            AField { group: "vessel"; key: "Kp"; label: "Крен Kp"; unit: "кН·м·с"; k: 1000 }
                            AField { group: "vessel"; key: "Mq"; label: "Дифферент Mq"; unit: "кН·м·с"; k: 1000 }
                        }
                        Sect { text: "Квадратичное демпфирование" }
                        Flow { width: parent.width; spacing: Theme.px(14)
                            AField { group: "vessel"; key: "Xuu"; label: "Вдоль Xuu"; unit: "кН·с²/м²"; k: 1000 }
                            AField { group: "vessel"; key: "Yvv"; label: "Поперёк Yvv"; unit: "кН·с²/м²"; k: 1000 }
                            AField { group: "vessel"; key: "Nrr"; label: "Рыскание Nrr"; unit: "кН·м·с²"; k: 1000 }
                        }
                        Sect { text: "Волны" }
                        Flow { width: parent.width; spacing: Theme.px(14)
                            AField { group: "vessel"; key: "waveReflection"; label: "Коэфф. отражения волн"; unit: "—"; hint: "Для дрейфовой силы волн" }
                            AField { group: "vessel"; key: "raoHeave"; label: "RAO вертикальных (heave)"; unit: "—" }
                            AField { group: "vessel"; key: "raoRoll"; label: "RAO крена"; unit: "—" }
                            AField { group: "vessel"; key: "raoPitch"; label: "RAO дифферента"; unit: "—" }
                        }
                    }
                    // --- 3. движители
                    Column { id: p3; visible: pg.tab === 3; width: parent.width; spacing: Theme.px(8)
                        Hint { text: "Координаты — метры от точки управления: x к носу, y на правый борт. Упоры вводятся в килоньютонах. Угол фиксированного движителя: 0° — вперёд, 90° — вправо. Запретные сектора азимутальной колонки — пары «от:до» в градусах от носа по часовой, через точку с запятой, например 80:100; 260:280." }
                        Repeater {
                            model: pg.prof ? pg.prof.thrusters.length : 0
                            delegate: Rectangle {
                                id: card
                                required property int index
                                width: p3.width; radius: 8; color: Theme.panel2; border.color: Theme.line
                                height: cc.height + Theme.px(20)
                                readonly property var t: pg.prof.thrusters[index]
                                Column {
                                    id: cc; x: Theme.px(10); y: Theme.px(10); width: parent.width - Theme.px(20); spacing: Theme.px(4)
                                    RowLayout { width: parent.width; spacing: 8
                                        Text { text: "Движитель " + (card.t.id !== "" ? card.t.id : "№" + (card.index + 1)); color: Theme.text; font.pixelSize: Theme.px(16); font.bold: true }
                                        Item { Layout.fillWidth: true }
                                        Btn { text: "Копия"; onClicked: pg.copyThruster(card.index) }
                                        Btn { text: "Удалить"; danger: true; onClicked: pg.removeThruster(card.index) } }
                                    Seg { width: Theme.px(360); model: ["Фиксированный", "Туннельный", "Азимутальный"]
                                          current: card.t.type === "fixed" ? 0 : card.t.type === "tunnel" ? 1 : 2
                                          onPicked: (i) => pg.setThr(card.index, "type", ["fixed", "tunnel", "azimuth"][i]) }
                                    Flow { width: parent.width; spacing: Theme.px(14)
                                        AField { thr: card.index; key: "id"; label: "Обозначение"; isString: true; use: "м"; hint: "Совпадает с обозначением в линии вывода на контроллер" }
                                        ABool { thr: card.index; key: "enabled"; label: "В работе" }
                                        AField { thr: card.index; key: "x"; label: "x (к носу)"; unit: "м" }
                                        AField { thr: card.index; key: "y"; label: "y (на правый борт)"; unit: "м" }
                                        AField { thr: card.index; key: "z"; label: "z (вниз от точки управления)"; unit: "м"; use: "спр" }
                                        AField { thr: card.index; visible: card.t.type !== "azimuth"; key: "fixedAngleDeg"; label: "Направление упора"; unit: "°" }
                                        AField { thr: card.index; key: "maxForward"; label: "Макс. упор вперёд"; unit: "кН"; k: 1000 }
                                        AField { thr: card.index; key: "maxReverse"; label: "Макс. упор назад"; unit: "кН"; k: 1000 }
                                        AField { thr: card.index; key: "powerMaxKW"; label: "Мощность при макс. упоре"; unit: "кВт"; hint: "Для ограничения по мощности электростанции. 0 — не учитывать" }
                                        AField { thr: card.index; key: "timeConstS"; label: "Постоянная времени упора"; unit: "с" }
                                        AField { thr: card.index; key: "rateFracPerS"; label: "Скорость изменения упора"; unit: "доля/с" }
                                        AField { thr: card.index; visible: card.t.type === "azimuth"; key: "azRateDegS"; label: "Скорость поворота колонки"; unit: "°/с" }
                                        AField { thr: card.index; key: "weight"; label: "Вес при распределении"; unit: "—"; hint: "Больше — движитель загружается меньше" }
                                    }
                                    Row { visible: card.t.type === "azimuth"; spacing: 8; height: Theme.px(36)
                                        Text { anchors.verticalCenter: parent.verticalCenter; width: Theme.px(215); text: "Запретные сектора"; color: Theme.text; font.pixelSize: Theme.px(14) }
                                        TextField { id: ftf; width: Theme.px(300); height: Theme.px(32); text: pg.forbiddenText(card.t.forbidden); color: Theme.text; font.pixelSize: Theme.px(14)
                                            background: Rectangle { color: Theme.panel2; radius: 5; border.color: ftf.activeFocus ? Theme.accent : Theme.line }
                                            onEditingFinished: { var r = pg.parseForbidden(text); if (r === null) { pg.say("Запретные сектора: формат «от:до; от:до»", true); text = pg.forbiddenText(card.t.forbidden) } else pg.setThr(card.index, "forbidden", r) } }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: "°"; color: Theme.sub; font.pixelSize: Theme.px(13) } }
                                }
                            }
                        }
                        Btn { text: "Добавить движитель"; onClicked: pg.addThruster() }
                    }
                    // --- 4. условия
                    Column { id: p4; visible: pg.tab === 4; width: parent.width; spacing: Theme.px(2)
                        Hint { text: "Сведения о месте и условиях, влияющих на судно. Пока в модели они не используются (метка «С»), но хранятся вместе с профилем, попадают в проверку и будут нужны при развитии модели." }
                        Flow { width: parent.width; spacing: Theme.px(14)
                            AField { group: "loading"; key: "waterDepth"; label: "Глубина места"; unit: "м"; use: "спр"; hint: "При глубине менее 3 осадок растут присоединённые массы и демпфирование — в модели это пока не учтено" }
                            AField { group: "loading"; key: "freeboard"; label: "Надводный борт"; unit: "м"; use: "спр" }
                            AField { group: "loading"; key: "windageHeight"; label: "Высота центра парусности"; unit: "м"; use: "спр"; hint: "Нужна для расчёта крена от ветра; в трёх степенях свободы управления не используется" }
                            AField { group: "loading"; key: "iceThicknessCm"; label: "Лёд"; unit: "см"; use: "спр" }
                        }
                        Sect { text: "Примечания" }
                        TextArea { width: Math.min(parent.width, Theme.px(760)); height: Theme.px(120); wrapMode: TextEdit.Wrap; color: Theme.text; font.pixelSize: Theme.px(14)
                                   text: pg.prof ? pg.prof.notes : ""; placeholderText: "Источник данных, дата замеров, кто вводил"; placeholderTextColor: Theme.sub
                                   background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line }
                                   onEditingFinished: if (pg.prof && text !== pg.prof.notes) { pg.prof.notes = text; pg.dirty = true; pg.profChanged() } }
                    }
                    // --- 5. проверка
                    Column { id: p5; visible: pg.tab === 5; width: parent.width; spacing: Theme.px(6)
                        Hint { text: "Проверка выполняется в ядре. Ошибки не дают сохранить профиль; предупреждения — только на внимание. Нажмите «Проверить» после правок." }
                        Sect { text: "Замечания" }
                        Text { visible: pg.issues.length === 0; text: "Замечаний нет"; color: Theme.ok; font.pixelSize: Theme.px(14) }
                        Repeater { model: pg.issues
                            delegate: Text { required property var modelData; width: p5.width; wrapMode: Text.Wrap; font.pixelSize: Theme.px(14)
                                             color: modelData.error ? Theme.bad : Theme.warn
                                             text: (modelData.error ? "Ошибка · " : "Предупреждение · ") + modelData.field + ": " + modelData.text } }
                        Sect { text: "Оценки для модели" }
                        Repeater { model: pg.estimates
                            delegate: Rectangle { required property var modelData; width: p5.width; height: ec.height + 8; color: "transparent"; border.color: Theme.line; border.width: 0
                                Column { id: ec; width: parent.width; spacing: 0
                                    Row { spacing: 10; Text { text: modelData.label; color: Theme.text; font.pixelSize: Theme.px(14); width: Math.min(p5.width * 0.55, Theme.px(480)); wrapMode: Text.Wrap }
                                          Text { text: modelData.value; color: Theme.accent; font.pixelSize: Theme.px(14); font.bold: true } }
                                    Text { visible: modelData.note !== ""; text: modelData.note; color: Theme.sub; font.pixelSize: Theme.px(12); width: parent.width; wrapMode: Text.Wrap } } } }
                        Hint { text: "Оценки пересчитываются при «Проверить» и «Сохранить». Предельный ветер — ориентир по одним только усилиям движителей, не заменяет анализ возможностей по классу DP." }
                    }
                    // --- 6. журнал
                    Column { id: p6; visible: pg.tab === 6; width: parent.width; spacing: Theme.px(4)
                        Hint { text: "Журнал ведётся в ядре (файл admin_audit.log): входы, неудачные попытки, смена пароля, сохранённые профили с перечнем изменённых полей. Пароли в журнал не пишутся." }
                        Repeater { model: pg.auditLines
                            delegate: Text { required property string modelData; width: p6.width; wrapMode: Text.Wrap; text: modelData; color: Theme.text; font.pixelSize: Theme.px(12); font.family: Theme.mono } }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ диалоги
    Popup {
        id: chpw
        modal: true; anchors.centerIn: Overlay.overlay; width: Theme.px(420); padding: Theme.px(16)
        background: Rectangle { color: Theme.panel; radius: 8; border.color: Theme.line }
        contentItem: Column {
            spacing: Theme.px(8)
            Text { text: "Смена пароля администратора"; color: Theme.text; font.pixelSize: Theme.px(18); font.bold: true }
            TextField { id: oldp; width: parent.width; echoMode: TextInput.Password; placeholderText: "Текущий пароль"; placeholderTextColor: Theme.sub; color: Theme.text
                        background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line } }
            TextField { id: newp; width: parent.width; echoMode: TextInput.Password; placeholderText: "Новый пароль (не короче 8 символов)"; placeholderTextColor: Theme.sub; color: Theme.text
                        background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line } }
            TextField { id: newp2; width: parent.width; echoMode: TextInput.Password; placeholderText: "Повторите новый пароль"; placeholderTextColor: Theme.sub; color: Theme.text
                        background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line } }
            Row { spacing: 8
                Btn { text: "Сменить"; active: true; onClicked: {
                    if (newp.text !== newp2.text) { pg.say("Новые пароли не совпадают", true); return }
                    pg.send("chpw", { old: oldp.text, "new": newp.text }, function (r) { if (r.ok) pg.say("Пароль изменён", false); else pg.say(r.err, true) })
                    oldp.text = ""; newp.text = ""; newp2.text = ""; chpw.close() } }
                Btn { text: "Отмена"; onClicked: { oldp.text = ""; newp.text = ""; newp2.text = ""; chpw.close() } } }
        }
    }
    Popup {      // пароль уровня «Старший»: если задан, настройки датчиков и расчётов требуют его входа (оператор — только управление)
        id: chief
        modal: true; anchors.centerIn: Overlay.overlay; width: Theme.px(440); padding: Theme.px(16)
        background: Rectangle { color: Theme.panel; radius: 8; border.color: Theme.line }
        contentItem: Column {
            spacing: Theme.px(8)
            Text { text: "Пароль уровня «Старший»"; color: Theme.text; font.pixelSize: Theme.px(18); font.bold: true }
            Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(13)
                   text: "Пока пароль задан, команды настройки (датчики, тесты систем положения, ограничения, расчёты) принимаются только после входа «Старшего» или администратора. Обычное управление (точка, режимы, квитирование) не затрагивается. «Старший» не видит профиль судна и не меняет пароли." }
            TextField { id: cp1; width: parent.width; echoMode: TextInput.Password; placeholderText: "Новый пароль «Старшего» (не короче 8 символов)"; placeholderTextColor: Theme.sub; color: Theme.text
                        background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line } }
            TextField { id: cp2; width: parent.width; echoMode: TextInput.Password; placeholderText: "Повторите пароль"; placeholderTextColor: Theme.sub; color: Theme.text
                        background: Rectangle { color: Theme.panel2; radius: 5; border.color: Theme.line } }
            Row { spacing: 8
                Btn { text: "Задать"; active: true; onClicked: {
                    if (cp1.text !== cp2.text) { pg.say("Пароли «Старшего» не совпадают", true); return }
                    pg.send("csetup", { pw: cp1.text }, function (r) { if (r.ok) pg.say("Пароль «Старшего» задан", false); else pg.say(r.err, true) })
                    cp1.text = ""; cp2.text = ""; chief.close() } }
                Btn { text: "Снять уровень"; onClicked: { pg.send("cclear", {}, function (r) { if (r.ok) pg.say("Уровень «Старший» снят: настройки доступны без входа", false); else pg.say(r.err, true) }); chief.close() } }
                Btn { text: "Отмена"; onClicked: { cp1.text = ""; cp2.text = ""; chief.close() } } }
        }
    }
    Popup {
        id: closeAsk
        modal: true; anchors.centerIn: Overlay.overlay; width: Theme.px(420); padding: Theme.px(16)
        background: Rectangle { color: Theme.panel; radius: 8; border.color: Theme.line }
        contentItem: Column {
            spacing: Theme.px(10)
            Text { width: Theme.px(388); wrapMode: Text.Wrap; text: "Есть несохранённые правки. Выйти без сохранения?"; color: Theme.text; font.pixelSize: Theme.px(16) }
            Row { spacing: 8
                Btn { text: "Выйти без сохранения"; danger: true; onClicked: { closeAsk.close(); pg.dirty = false; pg.close() } }
                Btn { text: "Вернуться"; active: true; onClicked: closeAsk.close() } }
        }
    }
}
