import QtQuick
import QtQuick.Controls

// Источники данных: откуда физически берутся данные на этом компьютере — сетевые интерфейсы, COM/USB-порты — и как они привязаны
// к входам внешней ДП и к каналам записи обмена. Проверка линии только слушает: в линию ничего не отправляется.
// ⚠ Список портов и интерфейсов проверен на Linux; на macOS ожидаются /dev/cu.*, на Windows COM1…COM64 (не проверялось).
Item {
    id: pg
    property var sess: null
    readonly property bool isAdmin: sess ? sess.admin : false
    property bool embedded: false
    readonly property var st: backend.s
    property var cap: null
    property var ext: null
    property string selPort: ""
    property string selIp: ""
    property string msg: ""
    property bool msgBad: false
    property var probe: ({ type: "serial", bind: "0.0.0.0", port: 0, group: "", host: "", dest: "", device: "", baud: 9600, parity: "N", stop: 1 })
    property int prev: 0
    property string secText: "5"
    readonly property var list: cap && cap.src && cap.src.list ? cap.src.list : null
    readonly property var test: cap && cap.src ? cap.src.test : null
    readonly property bool recording: !!cap && cap.rec === true

    function parse() {
        try { cap = st.capJson && st.capJson !== "" ? JSON.parse(st.capJson) : null } catch (e) { cap = null }
        try { ext = st.extJson && st.extJson !== "" ? JSON.parse(st.extJson) : null } catch (e) { ext = null }
    }
    onStChanged: parse()
    Component.onCompleted: parse()
    onVisibleChanged: { if (visible) { backend.command("src watch on"); backend.command("src list") } else backend.command("src watch off") }

    function say(t, bad) { msg = t; msgBad = bad }
    // входы внешней ДП: обновить один вход и отправить настройку целиком
    function extSet(i, fn) {
        if (!ext || !ext.cfg) return
        var c = JSON.parse(JSON.stringify(ext.cfg)); fn(c.inputs[i])
        backend.agentAudit("ext setup (источник данных изменён оператором)")
        backend.command("ext setup " + JSON.stringify(c)); say("Применено к входу внешней ДП. Результат — в журнале событий.", false)
    }
    function capSet(ci, which, fn) {
        if (!cap || !cap.cfg) return
        var c = JSON.parse(JSON.stringify(cap.cfg)); fn(c.channels[ci][which])
        backend.agentAudit("cap setup (источник данных изменён оператором)")
        backend.command("cap setup " + JSON.stringify(c)); say("Применено к каналу записи. Результат — в журнале событий.", false)
    }
    function epOfInput(t) {
        var tr = t.transport
        if (tr.type === "udp") return { type: "udp", bind: tr.bind, port: tr.port, group: "", host: "", dest: "", device: "", baud: 9600, parity: "N", stop: 1 }
        if (tr.type === "tcp") return { type: "tcpc", bind: "0.0.0.0", port: tr.port, group: "", host: tr.host, dest: "", device: "", baud: 9600, parity: "N", stop: 1 }
        return { type: "serial", bind: "0.0.0.0", port: 0, group: "", host: "", dest: "", device: tr.device, baud: tr.baud, parity: "N", stop: 1 }
    }
    function epText(e) {
        if (!e) return "—"
        if (e.type === "udp") return "UDP " + e.bind + ":" + e.port + (e.group ? " группа " + e.group : "") + (e.dest ? " → " + e.dest : "")
        if (e.type === "tcpc") return "TCP-клиент " + e.host + ":" + e.port
        if (e.type === "tcps") return "TCP-сервер " + e.bind + ":" + e.port
        return "COM " + (e.device === "" ? "(порт не выбран)" : e.device) + " " + e.baud + " бод"
    }
    function toProbe(e) { probe = JSON.parse(JSON.stringify(e)); prev++; say("Линия скопирована в форму проверки ниже.", false) }
    function runTest() {
        var e = probe
        if (e.type === "serial" && e.device === "") { say("Выберите COM-порт в списке или впишите его", true); return }
        if (e.type !== "serial" && !(e.port > 0 && e.port < 65536)) { say("Порт — от 1 до 65535", true); return }
        if (e.type === "tcpc" && e.host === "") { say("Не задан адрес сервера", true); return }
        var sec = Math.max(1, Math.min(30, Math.round(Number(secText)) || 5))
        backend.agentAudit("src test (проверка линии)")
        backend.command("src test " + JSON.stringify(e) + " " + sec); say("", false)
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.height + 20; clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }
        Column {
            id: col; width: parent.width - 14; spacing: Theme.px(10)

            Panel {
                width: parent.width; height: ifCol.height + Theme.px(52)
                title: "Сетевые интерфейсы этого компьютера"
                Column { id: ifCol; width: parent.width; spacing: Theme.px(4)
                    Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(12)
                           text: "Адрес интерфейса нужен, чтобы слушать данные именно на сетевой карте, подключённой к линии судна. Нажмите на строку, затем «Слушать на этом адресе» у нужного входа ниже." }
                    Text { visible: !pg.list; color: Theme.sub; font.pixelSize: Theme.px(13); text: "Загрузка списка…" }
                    Text { visible: !!pg.list && pg.list.ifs.length === 0; color: Theme.warn; font.pixelSize: Theme.px(13); text: "Интерфейсы не найдены (на Windows список пока не поддерживается: адрес вводится вручную)" }
                    Repeater {
                        model: pg.list ? pg.list.ifs.length : 0
                        delegate: Rectangle {
                            id: ir
                            required property int index
                            readonly property var f: pg.list.ifs[index]
                            width: ifCol.width; height: Theme.px(28); radius: 4; color: pg.selIp === f.ip ? Theme.panel2 : "transparent"; border.color: pg.selIp === f.ip ? Theme.accent : "transparent"
                            Row { anchors.verticalCenter: parent.verticalCenter; x: 6; spacing: 12
                                Text { width: Theme.px(120); text: ir.f.name; color: Theme.text; font.pixelSize: Theme.px(13); font.bold: true }
                                Text { width: Theme.px(150); text: ir.f.ip; color: Theme.accent; font.pixelSize: Theme.px(13); font.family: Theme.mono }
                                Text { width: Theme.px(150); text: ir.f.up ? "включён" : "нет связи"; color: ir.f.up ? Theme.ok : Theme.warn; font.pixelSize: Theme.px(12) }
                                Text { text: ir.f.loop ? "внутренний (этот компьютер)" : ""; color: Theme.sub; font.pixelSize: Theme.px(12) }
                            }
                            MouseArea { anchors.fill: parent; onClicked: pg.selIp = pg.selIp === ir.f.ip ? "" : ir.f.ip }
                        }
                    }
                }
            }

            Panel {
                width: parent.width; height: pCol.height + Theme.px(52)
                title: "COM / USB-порты"
                Column { id: pCol; width: parent.width; spacing: Theme.px(4)
                    Row { spacing: 8
                        Btn { text: "Обновить список"; onClicked: backend.command("src list") }
                        Text { anchors.verticalCenter: parent.verticalCenter; color: Theme.sub; font.pixelSize: Theme.px(12); text: "Подключите адаптер и нажмите «Обновить». Нажмите на порт, затем «Подставить выбранный порт» у нужной линии ниже." }
                    }
                    Text { visible: !!pg.list && pg.list.ports.length === 0; width: parent.width; wrapMode: Text.Wrap; color: Theme.warn; font.pixelSize: Theme.px(13); text: "Портов не найдено. Проверьте адаптер и драйвер (для USB-COM на Mac — драйвер чипа адаптера, порты вида /dev/cu.usbserial-…)." }
                    Repeater {
                        model: pg.list ? pg.list.ports.length : 0
                        delegate: Rectangle {
                            id: pr
                            required property int index
                            readonly property var p: pg.list.ports[index]
                            width: pCol.width; height: Theme.px(28); radius: 4; color: pg.selPort === p.name ? Theme.panel2 : "transparent"; border.color: pg.selPort === p.name ? Theme.accent : "transparent"
                            Row { anchors.verticalCenter: parent.verticalCenter; x: 6; spacing: 12
                                Text { width: Theme.px(360); elide: Text.ElideRight; text: pr.p.name; color: Theme.accent; font.pixelSize: Theme.px(13); font.family: Theme.mono }
                                Text { text: pr.p.kind; color: Theme.sub; font.pixelSize: Theme.px(12) }
                            }
                            MouseArea { anchors.fill: parent; onClicked: pg.selPort = pg.selPort === pr.p.name ? "" : pr.p.name }
                        }
                    }
                }
            }

            Panel {
                width: parent.width; height: bCol.height + Theme.px(52)
                title: "Привязка: откуда берётся каждый сигнал"
                Column { id: bCol; width: parent.width; spacing: Theme.px(6)
                    Text { visible: !pg.isAdmin; width: parent.width; wrapMode: Text.Wrap; color: Theme.warn; font.pixelSize: Theme.px(13); text: "Менять привязку может администратор — войдите вверху страницы «Администрирование»." }
                    Text { text: "Входы внешней ДП"; color: Theme.accent; font.pixelSize: Theme.px(13); font.bold: true }
                    Text { visible: !pg.ext || !pg.ext.configured; color: Theme.sub; font.pixelSize: Theme.px(13); text: "Связь с внешней ДП не настроена (вкладка «Внешняя ДП: связь»)." }
                    Repeater {
                        model: pg.ext && pg.ext.configured ? pg.ext.cfg.inputs.length : 0
                        delegate: Rectangle {
                            id: br
                            required property int index
                            readonly property var inp: pg.ext.cfg.inputs[index]
                            readonly property var sigs: { var r = []; for (var i = 0; i < pg.ext.cfg.fields.length; ++i) { var f = pg.ext.cfg.fields[i]; if (f.ch === "" || f.ch === inp.id) r.push(f.name) } return r }
                            width: bCol.width; height: bc.height + 12; radius: 6; color: Theme.panel2; border.color: Theme.line
                            Column { id: bc; x: 8; y: 6; width: parent.width - 16; spacing: 4
                                Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.text; font.pixelSize: Theme.px(13); text: br.inp.id + " (" + (br.inp.kind === "gyro" ? "курс" : "положение") + ") · " + pg.epText(pg.epOfInput(br.inp)) }
                                Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(12); text: "Сигналы: " + (br.sigs.length ? br.sigs.join(", ") : "только положение/курс") }
                                Row { spacing: 8
                                    Btn { text: "Подставить выбранный порт"; px: Theme.px(12); enabledBtn: pg.isAdmin && pg.selPort !== "" && br.inp.transport.type === "serial"; onClicked: pg.extSet(br.index, function (t) { t.transport.device = pg.selPort }) }
                                    Btn { text: "Слушать на этом адресе"; px: Theme.px(12); enabledBtn: pg.isAdmin && pg.selIp !== "" && br.inp.transport.type === "udp"; onClicked: pg.extSet(br.index, function (t) { t.transport.bind = pg.selIp }) }
                                    Btn { text: "В форму проверки"; px: Theme.px(12); onClicked: pg.toProbe(pg.epOfInput(br.inp)) }
                                }
                            }
                        }
                    }
                    Text { text: "Каналы записи обмена"; color: Theme.accent; font.pixelSize: Theme.px(13); font.bold: true }
                    Text { visible: !pg.cap || pg.cap.cfg.channels.length === 0; color: Theme.sub; font.pixelSize: Theme.px(13); text: "Каналов записи нет (вкладка «Запись обмена»)." }
                    Text { visible: pg.recording; color: Theme.warn; font.pixelSize: Theme.px(12); text: "Идёт запись: линии менять нельзя." }
                    Repeater {
                        model: pg.cap ? pg.cap.cfg.channels.length : 0
                        delegate: Rectangle {
                            id: cr
                            required property int index
                            readonly property var ch: pg.cap.cfg.channels[index]
                            readonly property var live: pg.cap.ch && pg.cap.ch[index] ? pg.cap.ch[index] : null
                            width: bCol.width; height: cc.height + 12; radius: 6; color: Theme.panel2; border.color: Theme.line
                            Column { id: cc; x: 8; y: 6; width: parent.width - 16; spacing: 4
                                Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.text; font.pixelSize: Theme.px(13); font.bold: true; text: cr.ch.id + " · " + (cr.ch.mode === "tap" ? "приём" : cr.ch.mode === "bridge" ? "в разрыв" : "опрос Modbus") }
                                Repeater { model: cr.ch.b ? ["a", "b"] : ["a"]
                                    delegate: Column { id: ln; required property string modelData; width: cc.width; spacing: 3
                                        readonly property var e: cr.ch[modelData]
                                        readonly property var lv: cr.live ? cr.live[modelData] : null
                                        Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.text; font.pixelSize: Theme.px(13)
                                               text: (cr.ch.b ? "Линия " + modelData.toUpperCase() + ": " : "") + pg.epText(ln.e) + (ln.lv ? "  ·  " + (ln.lv.up ? "связь есть" : (ln.lv.err ? ln.lv.err : "нет связи")) + ", принято " + ln.lv.rx + " Б" : "") }
                                        Row { spacing: 8
                                            Btn { text: "Подставить выбранный порт"; px: Theme.px(12); enabledBtn: pg.isAdmin && !pg.recording && pg.selPort !== "" && ln.e.type === "serial"; onClicked: pg.capSet(cr.index, ln.modelData, function (t) { t.device = pg.selPort }) }
                                            Btn { text: "Слушать на этом адресе"; px: Theme.px(12); enabledBtn: pg.isAdmin && !pg.recording && pg.selIp !== "" && (ln.e.type === "udp" || ln.e.type === "tcps"); onClicked: pg.capSet(cr.index, ln.modelData, function (t) { t.bind = pg.selIp }) }
                                            Btn { text: "В форму проверки"; px: Theme.px(12); onClicked: pg.toProbe(ln.e) }
                                        }
                                    } }
                            }
                        }
                    }
                    Text { visible: pg.msg !== ""; width: parent.width; wrapMode: Text.Wrap; color: pg.msgBad ? Theme.bad : Theme.ok; font.pixelSize: Theme.px(13); text: pg.msg }
                }
            }

            Panel {
                width: parent.width; height: tCol.height + Theme.px(52)
                title: "Проверка линии"
                Column { id: tCol; width: parent.width; spacing: Theme.px(8)
                    Text { width: parent.width; wrapMode: Text.Wrap; color: Theme.sub; font.pixelSize: Theme.px(12)
                           text: "Открывает линию на несколько секунд и только слушает: показывает, открылась ли она, идёт ли поток и сколько байт принято. Линию, которую уже использует связь с внешней ДП или запись обмена, проверять нельзя (порт занят): смотрите её состояние выше." }
                    CapEndpoint { ep: { pg.prev; return pg.probe } editable: pg.isAdmin; label: "Линия"; width: parent.width; onChanged: pg.prev++ }
                    Row { spacing: 8
                        Btn { text: "Подставить выбранный порт"; px: Theme.px(12); enabledBtn: pg.isAdmin && pg.selPort !== ""; onClicked: { pg.probe.type = "serial"; pg.probe.device = pg.selPort; pg.prev++ } }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "секунд"; color: Theme.sub; font.pixelSize: Theme.px(13) }
                        TextField { width: Theme.px(50); text: pg.secText; color: Theme.text; font.pixelSize: Theme.px(13); horizontalAlignment: TextInput.AlignRight; enabled: pg.isAdmin; background: Rectangle { color: Theme.panel; radius: 5; border.color: Theme.line }  onEditingFinished: pg.secText = text }
                        Btn { text: "Проверить"; active: true; enabledBtn: pg.isAdmin && !pg.recording && !(pg.test && pg.test.state === "run"); onClicked: pg.runTest() }
                    }
                    Text { visible: !!pg.test; width: parent.width; wrapMode: Text.Wrap; font.pixelSize: Theme.px(14); font.bold: true
                           color: pg.test && pg.test.state === "done" ? (pg.test.bytes > 0 ? Theme.ok : Theme.warn) : Theme.text
                           text: pg.test ? pg.test.desc + ": " + (pg.test.state === "run" ? "проверка идёт, " + pg.test.t + " из " + pg.test.total + " с, принято " + pg.test.bytes + " Б" : pg.test.verdict + " (принято " + pg.test.bytes + " Б" + (pg.test.peer ? ", от " + pg.test.peer : "") + ")") : "" }
                }
            }
        }
    }
}
